defmodule Refract.Classify.Score do
  @moduledoc false

  alias Refract.Classify.Candidate
  alias Refract.Classify.Result
  alias Refract.Table
  alias Refract.Table.Report.Line, as: ReportLine
  alias Refract.Table.Scan
  alias Refract.Table.Spec.Header
  alias Refract.Table.Spec.Row

  alias Refract.Shape

  @type pick :: :best | :first

  @type opt ::
          {:within, non_neg_integer()}
          | {:min_score, number()}
          | {:margin, number()}
          | {:values, boolean()}
          | {:pick, pick()}

  @spec validate_opts!(keyword()) :: keyword()

  def validate_opts!(opts) do
    opts =
      Keyword.validate!(opts,
        within: 100,
        min_score: 0.5,
        margin: 0.1,
        values: false,
        pick: :best
      )

    validate_pick(Keyword.fetch!(opts, :pick))
    validate_within(Keyword.fetch!(opts, :within))
    validate_fraction(Keyword.fetch!(opts, :min_score), :min_score)
    validate_fraction(Keyword.fetch!(opts, :margin), :margin)
    validate_values(Keyword.fetch!(opts, :values))

    opts
  end

  @spec run(Enumerable.t(), [Shape.t() | module()], [opt()]) :: Result.t()

  def run(raw, shapes, opts) do
    opts = validate_opts!(opts)

    within = Keyword.fetch!(opts, :within)
    min_score = Keyword.fetch!(opts, :min_score)
    margin = Keyword.fetch!(opts, :margin)
    values = Keyword.fetch!(opts, :values)
    pick = Keyword.fetch!(opts, :pick)

    resolved_shapes = resolve_shapes(shapes)
    sample = Enum.take(raw, within)
    prepared = Scan.prepare(sample)

    perform_pipeline(pick, resolved_shapes, sample, prepared, min_score, margin, values)
  end

  defp perform_pipeline(:best, shapes, sample, prepared, min_score, margin, values) do
    shapes
    |> Enum.map(&candidate(&1, sample, prepared, min_score, values))
    |> rank_candidates()
    |> verdict(margin)
  end

  defp perform_pipeline(:first, shapes, sample, prepared, min_score, margin, values) do
    case first_match(shapes, sample, prepared, min_score, values) do
      nil ->
        perform_pipeline(:best, shapes, sample, prepared, min_score, margin, values)

      {row, winner} ->
        others =
          for shape <- shapes, shape != winner.shape do
            candidate(shape, Enum.take(sample, row), Enum.take(prepared, row), min_score, values)
          end

        %Result{
          verdict: :match,
          shape: winner.shape,
          candidates:
            rank_candidates([
              winner
              | others
            ])
        }
    end
  end

  defp first_match(shapes, sample, prepared, min_score, values) do
    prepared
    |> Enum.with_index(1)
    |> Enum.find_value(fn {{line, normalised_line}, row} ->
      shapes
      |> Enum.flat_map(&matched_at(&1, line, normalised_line, row, sample, min_score, values))
      |> first_winner(row)
    end)
  end

  defp matched_at(shape, line, normalised_line, row, sample, min_score, values) do
    report = %{Header.report(shape.spec.header, line, normalised_line) | row: row}

    matched(report, shape, sample, min_score, values)
  end

  defp matched(%ReportLine{passed: false}, _shape, _sample, _min_score, _values), do: []

  defp matched(report, shape, sample, min_score, values) do
    candidate = scored(shape, report, sample, min_score, values)

    if candidate.status == :matched, do: [candidate], else: []
  end

  defp first_winner([], _row), do: nil
  defp first_winner(candidates, row), do: {row, Enum.max_by(candidates, & &1.score)}

  defp resolve_shapes(shapes) when is_list(shapes) and shapes != [] do
    Enum.map(shapes, &Shape.resolve/1)
  end

  defp resolve_shapes(shapes) do
    raise ArgumentError, "shapes must be a list of at least one shape, got: #{inspect(shapes)}"
  end

  defp candidate(shape, [], _prepared, _min_score, _values),
    do: Candidate.new(shape, :no_header, 0.0, nil, [])

  defp candidate(%Shape{spec: spec} = shape, sample, prepared, min_score, values) do
    reports = Scan.run_prepared(prepared, spec)

    case Enum.filter(reports, & &1.passed) do
      [] ->
        scored(shape, best_line(reports), sample, min_score, values)

      passing ->
        passing
        |> Enum.map(&scored(shape, &1, sample, min_score, values))
        |> Enum.max_by(& &1.score)
    end
  end

  defp best_line(reports) do
    Enum.max_by(reports, &map_size(Header.positions(&1)))
  end

  defp scored(shape, %ReportLine{passed: false} = header, _sample, _min_score, _values) do
    Candidate.new(shape, :no_header, share(shape, header), header, [])
  end

  defp scored(shape, header, sample, min_score, values) do
    rows = rows(shape, header, sample, values)
    score = share(shape, header) * pass_rate(rows)

    status = if(score >= min_score, do: :matched, else: :rows_failed)

    Candidate.new(shape, status, score, header, rows)
  end

  defp rows(shape, header, sample, values) do
    positions = Header.positions(header)

    sample
    |> Enum.with_index(1)
    |> Enum.drop(header.row)
    |> Enum.take_while(fn {line, _row} -> Table.match_stop(shape.spec, line) == :continue end)
    |> Enum.map(fn {line, row} -> row_report(shape, line, row, positions, values) end)
  end

  defp row_report(shape, line, row, positions, values) do
    %{Row.report(shape.spec.row, Table.ordered_row(line, positions), values: values) | row: row}
  end

  defp pass_rate([]), do: 1.0

  defp pass_rate(rows), do: Enum.count(rows, & &1.passed) / length(rows)

  defp rank_candidates(candidates),
    do: Enum.sort_by(candidates, &{status_rank(&1.status), -&1.score})

  defp status_rank(:matched), do: 0
  defp status_rank(:rows_failed), do: 1
  defp status_rank(:no_header), do: 2

  defp verdict(candidates, margin) do
    candidates
    |> Enum.filter(&(&1.status == :matched))
    |> decide(candidates, margin)
  end

  defp decide([], candidates, _margin) do
    top = hd(candidates)
    %Result{verdict: :unknown, reason: top.status, shape: closest(top), candidates: candidates}
  end

  defp decide([top], candidates, _margin) do
    %Result{verdict: :match, shape: top.shape, candidates: candidates}
  end

  defp decide([first, second | _], candidates, margin) do
    if first.score - second.score < margin do
      %Result{verdict: :ambiguous, reason: :within_margin, candidates: candidates}
    else
      %Result{verdict: :match, shape: first.shape, candidates: candidates}
    end
  end

  defp closest(%Candidate{header: nil}), do: nil

  defp closest(%Candidate{shape: shape, header: header}) do
    if Header.positions(header) == %{} do
      nil
    else
      shape
    end
  end

  defp share(%Shape{spec: spec}, header) do
    map_size(Header.positions(header)) / map_size(spec.header.columns)
  end

  defp validate_within(within) when is_integer(within) and within >= 0, do: :ok

  defp validate_within(within) do
    raise ArgumentError, "within must be a non negative integer, got: #{inspect(within)}"
  end

  defp validate_fraction(value, _name) when is_number(value) and value >= 0 and value <= 1,
    do: :ok

  defp validate_fraction(value, name) do
    raise ArgumentError, "#{name} must be a number from 0 to 1, got: #{inspect(value)}"
  end

  defp validate_values(values) when is_boolean(values), do: :ok

  defp validate_values(values) do
    raise ArgumentError, "values must be true or false, got: #{inspect(values)}"
  end

  defp validate_pick(pick) when pick in [:best, :first], do: :ok

  defp validate_pick(pick) do
    raise ArgumentError, "pick must be :best or :first, got: #{inspect(pick)}"
  end
end
