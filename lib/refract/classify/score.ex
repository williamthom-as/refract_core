defmodule Refract.Classify.Score do
  @moduledoc false

  alias Refract.Classify.Candidate
  alias Refract.Classify.Ctx
  alias Refract.Classify.Result
  alias Refract.Classify.Verdict
  alias Refract.Shape
  alias Refract.Table
  alias Refract.Table.Report
  alias Refract.Table.Scan
  alias Refract.Table.Spec.Header
  alias Refract.Table.Spec.Row

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

    validate_within(Keyword.fetch!(opts, :within))
    validate_fraction(Keyword.fetch!(opts, :min_score), :min_score)
    validate_fraction(Keyword.fetch!(opts, :margin), :margin)
    validate_values(Keyword.fetch!(opts, :values))
    validate_pick(Keyword.fetch!(opts, :pick))

    opts
  end

  @spec run(Enumerable.t(), [Shape.t() | module()], [opt()]) :: Result.t()

  def run(raw, shapes, opts) do
    opts = validate_opts!(opts)

    within = Keyword.fetch!(opts, :within)
    pick = Keyword.fetch!(opts, :pick)

    resolved_shapes = resolve_shapes(shapes)
    sample = Enum.take(raw, within)

    ctx = %Ctx{
      sample: sample,
      prepared: Scan.prepare(sample),
      min_score: Keyword.fetch!(opts, :min_score),
      margin: Keyword.fetch!(opts, :margin),
      values: Keyword.fetch!(opts, :values)
    }

    pick(pick, resolved_shapes, ctx)
  end

  defp pick(:best, shapes, %Ctx{margin: margin} = ctx) do
    shapes
    |> Enum.map(&candidate(&1, ctx))
    |> Verdict.best(margin)
  end

  defp pick(:first, shapes, ctx) do
    case first_match(shapes, ctx) do
      nil ->
        pick(:best, shapes, ctx)

      {row, winner} ->
        seen = %{ctx | sample: Enum.take(ctx.sample, row), prepared: Enum.take(ctx.prepared, row)}
        others = for shape <- shapes, shape != winner.shape, do: candidate(shape, seen)

        Verdict.first(winner, others)
    end
  end

  defp first_match(shapes, %Ctx{prepared: prepared} = ctx) do
    prepared
    |> Enum.with_index(1)
    |> Enum.find_value(fn {{line, normalised_line}, row} ->
      shapes
      |> Enum.map(&scored_at(&1, line, normalised_line, row, ctx))
      |> Enum.filter(&match?(%Candidate{status: :matched}, &1))
      |> first_winner(row)
    end)
  end

  defp scored_at(%Shape{spec: spec} = shape, line, normalised_line, row, ctx) do
    %{Header.report(spec.header, line, normalised_line) | row: row}
    |> scored(shape, ctx)
  end

  defp first_winner([], _row), do: nil
  defp first_winner(matched, row), do: {row, Enum.max_by(matched, & &1.score)}

  defp candidate(shape, %Ctx{sample: []}),
    do: %Candidate{shape: shape, status: :no_header, score: 0.0}

  defp candidate(%Shape{spec: spec} = shape, %Ctx{prepared: prepared} = ctx) do
    reports = Scan.run_prepared(prepared, spec)

    reports
    |> Enum.filter(& &1.passed)
    |> best_candidate(reports, shape, ctx)
  end

  defp best_candidate([], reports, shape, ctx) do
    reports
    |> Enum.max_by(&map_size(Header.positions(&1)))
    |> scored(shape, ctx)
  end

  defp best_candidate(passing, _reports, shape, ctx) do
    passing
    |> Enum.map(&scored(&1, shape, ctx))
    |> Enum.max_by(& &1.score)
  end

  defp scored(%Report.Line{passed: false} = header, shape, _ctx) do
    %Candidate{shape: shape, status: :no_header, score: share(header, shape), header: header}
  end

  defp scored(header, shape, %Ctx{min_score: min_score} = ctx) do
    rows = rows(header, shape, ctx)
    score = share(header, shape) * pass_rate(rows)

    %Candidate{
      shape: shape,
      status: status(score, min_score),
      score: score,
      header: header,
      rows: rows
    }
  end

  defp status(score, min_score) when score >= min_score, do: :matched
  defp status(_score, _min_score), do: :rows_failed

  defp rows(header, %Shape{spec: spec}, %Ctx{sample: sample, values: values}) do
    positions = Header.positions(header)

    sample
    |> Enum.with_index(1)
    |> Enum.drop(header.row)
    |> Enum.take_while(fn {line, _row} -> Table.match_stop(spec, line) == :continue end)
    |> Enum.map(fn {line, row} -> row_report(spec, line, row, positions, values) end)
  end

  defp row_report(spec, line, row, positions, values) do
    %{Row.report(spec.row, Table.ordered_row(line, positions), values: values) | row: row}
  end

  defp share(header, %Shape{spec: spec}) do
    map_size(Header.positions(header)) / map_size(spec.header.columns)
  end

  defp pass_rate([]), do: 1.0
  defp pass_rate(rows), do: Enum.count(rows, & &1.passed) / length(rows)

  defp resolve_shapes(shapes) when is_list(shapes) and shapes != [] do
    Enum.map(shapes, &Shape.resolve/1)
  end

  defp resolve_shapes(shapes) do
    raise ArgumentError, "shapes must be a list of at least one shape, got: #{inspect(shapes)}"
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
