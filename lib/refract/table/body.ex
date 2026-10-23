defmodule Refract.Table.Body do
  @moduledoc false

  alias Refract.Table
  alias Refract.Table.Report
  alias Refract.Table.Spec
  alias Refract.Table.Spec.Header
  alias Refract.Table.Spec.Row

  import Refract.String.Utils, only: [blank_line?: 1]

  defstruct [:spec, :positions, :values, :misses]

  @type step :: {:hit | :miss | :end, Refract.row(), Report.Line.t()}

  @type t :: %__MODULE__{
          spec: Spec.t(),
          positions: Header.positions(),
          values: boolean(),
          misses: :limited | :unlimited
        }

  @spec run(Enumerable.t(), Spec.t(), Header.positions(), boolean()) :: Enumerable.t()

  def run(numbered_lines, %Spec{} = spec, positions, values, opts \\ []) do
    opts = Keyword.validate!(opts, misses: :limited)

    misses = Keyword.fetch!(opts, :misses)

    body = %__MODULE__{spec: spec, positions: positions, values: values, misses: misses}

    Stream.transform(numbered_lines, 0, &step(&1, &2, body))
  end

  defp step(_numbered_line, :ended, _body), do: {:halt, :ended}

  defp step({line, row}, misses, %__MODULE__{spec: spec} = body) do
    spec
    |> Table.match_stop(line)
    |> line_step(line, row, misses, body)
  end

  defp line_step({:stop, _condition}, _line, _row, misses, _body), do: {:halt, misses}

  defp line_step(:continue, line, row, misses, body) do
    if blank_line?(line) do
      {[], misses}
    else
      scored(line, row, misses, body)
    end
  end

  defp scored(
         line,
         row,
         misses,
         %__MODULE__{spec: spec, positions: positions, values: values} = body
       ) do
    mapped_row = Table.ordered_row(line, positions)
    report = %{Row.report(spec.row, mapped_row, values: values) | row: row}

    counted(report, mapped_row, misses, limit(body))
  end

  defp limit(%__MODULE__{misses: :unlimited}), do: :unlimited
  defp limit(%__MODULE__{spec: spec}), do: spec.max_misses

  defp counted(%Report.Line{passed: true} = report, mapped_row, misses, _limit),
    do: {[{:hit, mapped_row, report}], misses}

  defp counted(report, mapped_row, misses, :unlimited),
    do: {[{:miss, mapped_row, report}], misses + 1}

  defp counted(report, mapped_row, misses, limit) when misses < limit,
    do: {[{:miss, mapped_row, report}], misses + 1}

  defp counted(report, mapped_row, _misses, _limit),
    do: {[{:end, mapped_row, report}], :ended}
end
