defmodule Refract.Table.Scan do
  @moduledoc false

  alias Refract.Table.Report
  alias Refract.Table.Spec
  alias Refract.Table.Spec.Header

  @spec run([Refract.raw_row()], Spec.t()) :: [Report.Line.t()]

  def run(lines, %Spec{header: header}) do
    lines
    |> Enum.with_index(1)
    |> Enum.map(fn {line, row} ->
      %{Header.report(header, line) | row: row}
    end)
  end
end
