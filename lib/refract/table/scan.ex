defmodule Refract.Table.Scan do
  @moduledoc false

  alias Refract.Table.Report
  alias Refract.Table.Spec
  alias Refract.Table.Spec.Header

  @type prepared :: [{Refract.raw_row(), [String.t() | nil]}]

  @spec run([Refract.raw_row()], Spec.t()) :: [Report.Line.t()]

  def run(lines, %Spec{} = spec) do
    lines
    |> prepare()
    |> run_prepared(spec)
  end

  @spec prepare([Refract.raw_row()]) :: prepared()

  def prepare(lines), do: Enum.map(lines, &{&1, Header.normalise_line(&1)})

  @spec run_prepared(prepared(), Spec.t()) :: [Report.Line.t()]

  def run_prepared(prepared, %Spec{header: header}) do
    prepared
    |> Enum.with_index(1)
    |> Enum.map(fn {{line, normalised_line}, row} ->
      %{Header.report(header, line, normalised_line) | row: row}
    end)
  end
end
