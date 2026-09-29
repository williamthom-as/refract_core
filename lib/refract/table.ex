defmodule Refract.Table do
  alias Refract.Table.Spec
  alias Refract.Table.Spec.Header
  alias Refract.Table.Spec.Row
  alias Refract.Table.Spec.Stop

  @spec spec(opts :: keyword()) :: Spec.t()

  def spec(opts), do: Spec.new(opts)

  @spec match_header(Spec.t(), [String.t()]) ::
          {:ok, Header.positions()} | {:error, Header.miss()}

  def match_header(%Spec{header: header}, columns) do
    Header.matches(header, columns)
  end

  @spec match_row(Spec.t(), Refract.row()) :: :ok | {:error, Row.miss()}

  def match_row(%Spec{row: row_spec}, row) do
    Row.matches(row_spec, row)
  end

  @spec match_stop(Spec.t(), Refract.raw_row()) :: :continue | {:stop, Stop.condition()}

  def match_stop(%Spec{stop: stop_spec}, row) do
    Stop.matches(stop_spec, row)
  end
end
