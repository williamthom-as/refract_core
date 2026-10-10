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

  @type opt ::
          {:within, non_neg_integer()}
          | {:min_score, number()}
          | {:margin, number()}
          | {:values, boolean()}

  @spec validate_opts!(keyword()) :: keyword()

  def validate_opts!(opts) do
    opts = Keyword.validate!(opts, within: 100, min_score: 0.5, margin: 0.1, values: false)

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

    resolved_shapes = resolve_shapes(shapes)
    sample = Enum.take(raw, within)
    prepared = Scan.prepare(sample)

    resolved_shapes
    |> Enum.map(&candidate(&1, sample, prepared, min_score, values))
    |> rank_candidates()
    |> verdict(margin)
  end

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
    header = best_line(Enum.filter(reports, & &1.passed)) || best_line(reports)

    scored(shape, header, sample, min_score, values)
  end

  defp best_line([]), do: nil

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
end
