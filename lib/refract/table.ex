defmodule Refract.Table do
  @moduledoc """
  allows for sophisticated table finding and parsing, providing the ability to describe a table
  by its columns, then find it anywhere in a file. useful if your file is not in a strict tabular
  format, or has multiple tables in it.

  header columns take aliases and regexes, rows take rules, stop ends the table.

  `locate` searches the first `within:` lines and streams the rows below

      spec =
        Refract.Table.spec(
          header: [columns: %{"sku" => ["sku"], "total" => ["line total", "total"]}],
          row: [match: %{"sku" => :integer, "total" => :number}],
          stop: [:blank]
        )

      {:ok, table} = Refract.CSV.locate("invoice.csv", spec)
      Enum.to_list(table.rows)
  """

  alias Refract.Table.Concat
  alias Refract.Table.Locate
  alias Refract.Table.Report
  alias Refract.Table.Scan

  alias Refract.Table.Spec
  alias Refract.Table.Spec.Header
  alias Refract.Table.Spec.Row
  alias Refract.Table.Spec.Stop

  defstruct [:header_row, :header, :columns, :rows]

  @type t :: %__MODULE__{
          header_row: pos_integer() | nil,
          header: [String.t()],
          columns: Header.positions(),
          rows: Enumerable.t()
        }

  @spec new(
          header_row :: pos_integer() | nil,
          header :: [String.t()],
          columns :: Header.positions(),
          rows :: Enumerable.t()
        ) :: t()

  def new(header_row, header, columns, rows) do
    %__MODULE__{
      header_row: header_row,
      header: header,
      columns: columns,
      rows: rows
    }
  end

  @spec spec(opts :: keyword()) :: Spec.t()

  def spec(opts), do: Spec.new(opts)

  @spec match_header(Spec.t(), columns :: [String.t()]) ::
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

  @spec ordered_row(Refract.raw_row(), Header.positions()) :: Refract.row()

  def ordered_row(row, positions) do
    Map.new(positions, fn {name, pos} -> {name, Enum.at(row, pos)} end)
  end

  @spec locate(Enumerable.t(), Spec.t(), keyword()) ::
          {:ok, t()} | {:error, {:header_not_found, Locate.header_miss()}}

  def locate(raw, %Spec{} = spec, opts \\ []), do: Locate.run(raw, spec, opts)

  @spec scan([Refract.raw_row()], Spec.t()) :: [Report.Line.t()]

  def scan(lines, %Spec{} = spec), do: Scan.run(lines, spec)

  @spec concat([t()]) :: t()

  def concat(tables), do: Concat.run(tables)
end
