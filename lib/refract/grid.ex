defmodule Refract.Grid do
  alias Refract.Grid.Classify
  alias Refract.Grid.Lookup

  alias Refract.Table
  alias Refract.Table.Locate
  alias Refract.Table.Spec

  defstruct [:rows, :height, :width]

  @type t :: %__MODULE__{
          rows: tuple(),
          height: pos_integer(),
          width: pos_integer()
        }

  @spec new(Enumerable.t()) :: t()

  def new(raw_rows) do
    lines = Enum.to_list(raw_rows)

    rows =
      lines
      |> Enum.map(&List.to_tuple/1)
      |> List.to_tuple()

    width =
      lines
      |> Enum.map(&length/1)
      |> Enum.max(fn -> 0 end)

    %__MODULE__{rows: rows, height: tuple_size(rows), width: width}
  end

  @spec table(t(), keyword()) :: [Refract.row()]

  def table(%__MODULE__{} = grid, opts \\ []), do: Lookup.table(grid, opts)

  @spec locate(Refract.Grid.t(), Spec.t()) ::
          {:error, {:header_not_found, Locate.header_miss()}} | {:ok, Table.t()}

  def locate(%__MODULE__{height: height} = grid, spec, opts \\ []) do
    opts = Keyword.put_new(opts, :within, height)

    converted_rows = rows_as_list(grid)

    Table.locate(converted_rows, spec, opts)
  end

  @spec cell(t(), String.t()) :: Refract.cell()

  def cell(%__MODULE__{} = grid, ref), do: Lookup.cell(grid, ref)

  @spec range(t(), String.t()) :: [Refract.raw_row()]

  def range(%__MODULE__{} = grid, range), do: Lookup.range(grid, range)

  @spec classify(t(), Spec.t()) :: [Classify.classified()]

  def classify(%__MODULE__{} = grid, %Spec{} = spec), do: Classify.classify(grid, spec)

  @spec explain(t(), Spec.t()) :: [Classify.explained()]

  def explain(%__MODULE__{} = grid, %Spec{} = spec), do: Classify.explain(grid, spec)

  @spec rows_as_list(t()) :: [[Refract.cell()]]

  def rows_as_list(%__MODULE__{rows: rows}) do
    for row <- Tuple.to_list(rows), do: Tuple.to_list(row)
  end
end
