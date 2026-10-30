defmodule Refract.Table.Body do
  @moduledoc false

  alias Refract.Table
  alias Refract.Table.Report
  alias Refract.Table.Spec
  alias Refract.Table.Spec.Header
  alias Refract.Table.Spec.Row

  import Refract.String.Utils, only: [blank_line?: 1]

  @enforce_keys [:spec, :positions, :values, :misses]

  defstruct [:spec, :positions, :values, :misses]

  @type step :: {:hit | :miss | :end, Refract.row(), Report.Line.t()}

  @type t :: %__MODULE__{
          spec: Spec.t(),
          positions: Header.positions(),
          values: boolean(),
          misses: :limited | :unlimited
        }

  @spec run(Enumerable.t(), pos_integer(), Spec.t(), Header.positions(), boolean(), keyword()) ::
          Enumerable.t()

  def run(raw, header_row, %Spec{} = spec, positions, values, opts \\ []) do
    opts = Keyword.validate!(opts, misses: :limited, indexing: :lines)

    misses = Keyword.fetch!(opts, :misses)
    indexing_mode = Keyword.fetch!(opts, :indexing)

    body = %__MODULE__{spec: spec, positions: positions, values: values, misses: misses}

    first_idx_num = first_index(indexing_mode)

    raw
    |> Stream.with_index(first_idx_num)
    |> Stream.drop(header_row)
    |> Stream.transform(0, &step(&1, &2, body))
  end

  defp first_index(:lines), do: 1
  defp first_index(:records), do: 0

  defp first_index(indexing) do
    raise ArgumentError, "indexing must be :lines or :records, got: #{inspect(indexing)}"
  end

  defp step(_numbered_line, :ended, _body), do: {:halt, :ended}

  defp step({line, row}, missed, %__MODULE__{spec: spec} = body) do
    spec
    |> Table.match_stop(line)
    |> line_step(line, row, missed, body)
  end

  defp line_step({:stop, _condition}, _line, _row, missed, _body), do: {:halt, missed}

  defp line_step(:continue, line, row, missed, body) do
    if blank_line?(line) do
      {[], missed}
    else
      scored(line, row, missed, body)
    end
  end

  defp scored(
         line,
         row,
         missed,
         %__MODULE__{spec: spec, positions: positions, values: values} = body
       ) do
    mapped_row = Table.ordered_row(line, positions)
    report = %{Row.report(spec.row, mapped_row, values: values) | row: row}

    counted(report, mapped_row, missed, limit(body))
  end

  defp limit(%__MODULE__{misses: :unlimited}), do: :unlimited
  defp limit(%__MODULE__{spec: spec}), do: spec.max_misses

  defp counted(%Report.Line{passed: true} = report, mapped_row, missed, _limit),
    do: {[{:hit, mapped_row, report}], missed}

  defp counted(report, mapped_row, missed, :unlimited),
    do: {[{:miss, mapped_row, report}], missed + 1}

  defp counted(report, mapped_row, missed, limit) when missed < limit,
    do: {[{:miss, mapped_row, report}], missed + 1}

  defp counted(report, mapped_row, _missed, _limit),
    do: {[{:end, mapped_row, report}], :ended}
end
