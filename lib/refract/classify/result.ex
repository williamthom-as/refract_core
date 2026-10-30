defmodule Refract.Classify.Result do
  @moduledoc """
  what classify decided for a file and why (verdict, reason, shape matched and every
  candidate checked), and the reader it was read with (`{module, opts}`, nil from `lines`)
  """

  alias Refract.Classify.Candidate
  alias Refract.Classify.Drift
  alias Refract.Classify.Facts
  alias Refract.Classify.Marker
  alias Refract.Shape
  alias Refract.Table.Report

  import Refract.String.Utils, only: [text: 1]

  @type verdict :: :match | :ambiguous | :unknown

  @type reason ::
          :rows_failed | :no_header | :within_margin | :markers | :wider_header | :most_columns

  @type t :: %__MODULE__{
          verdict: verdict(),
          reason: reason() | nil,
          shape: Shape.t() | nil,
          file: Facts.t() | nil,
          drift: Drift.t() | nil,
          reader: {module(), keyword()} | nil,
          candidates: [Candidate.t()]
        }

  @enforce_keys [:verdict]

  defstruct [:verdict, :reason, :shape, :file, :drift, :reader, candidates: []]

  @spec to_map(t()) :: map()

  def to_map(%__MODULE__{} = result) do
    %{
      path: path(result.file),
      verdict: result.verdict,
      reason: result.reason,
      shape: shape(result.shape),
      drift: drift(result.drift),
      reader: reader(result.reader),
      candidates: Enum.map(result.candidates, &candidate/1)
    }
  end

  defp path(nil), do: nil
  defp path(%Facts{path: path}), do: path

  defp shape(nil), do: nil
  defp shape(%Shape{name: name, version: version}), do: %{name: name, version: version}

  defp drift(nil), do: nil

  defp drift(%Drift{missing: missing, extra: extra, others: others}) do
    %{
      missing: missing,
      extra: cells(extra),
      others: Map.new(others, fn {column, found} -> {column, cells(found)} end)
    }
  end

  defp reader(nil), do: nil

  defp reader({module, _opts}), do: inspect(module)

  defp candidate(%Candidate{shape: shape, status: status, score: score} = candidate) do
    %{
      shape: shape.name,
      status: status,
      score: score,
      header_line: header_line(candidate.header),
      markers: Enum.map(candidate.markers, &marker/1)
    }
  end

  defp header_line(%Report.Line{passed: true, row: row}), do: row
  defp header_line(_header), do: nil

  defp marker(%Marker{marker: marker, pattern: pattern, passed: passed}),
    do: %{marker: marker, pattern: inspect(pattern), passed: passed}

  defp cells(cells), do: Enum.map(cells, fn {index, cell} -> [index, text(cell)] end)
end
