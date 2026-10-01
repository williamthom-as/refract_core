defmodule Refract.Rows do
  import Refract.Utils, only: [truthy?: 1]

  alias Refract.String.Utils

  alias Refract.String.Utils

  @spec update(
          Enumerable.t(),
          String.t() | [String.t()],
          (Refract.cell() -> Refract.cell()),
          keyword()
        ) :: Enumerable.t()

  def update(rows, column, fun, opts \\ []) do
    skip_blank = Keyword.get(opts, :skip_blank, false)
    columns = List.wrap(column)

    Stream.map(rows, fn row ->
      Enum.reduce(columns, row, fn col, acc ->
        value = Map.fetch!(acc, col)

        if skip_blank and Utils.blank?(value) do
          acc
        else
          Map.put(acc, col, fun.(value))
        end
      end)
    end)
  end

  @spec put(Enumerable.t(), String.t(), (Refract.row() -> Refract.cell())) :: Enumerable.t()

  def put(rows, column, fun) do
    Stream.map(rows, fn row ->
      Map.put(row, column, fun.(row))
    end)
  end

  @spec copy(Enumerable.t(), String.t(), String.t()) :: Enumerable.t()

  def copy(rows, from_column, to_column) do
    Stream.map(rows, fn row ->
      Map.put(row, to_column, Map.fetch!(row, from_column))
    end)
  end

  @spec rename(Enumerable.t(), %{String.t() => String.t()}) :: Enumerable.t()

  def rename(rows, rename_columns) do
    Stream.map(rows, fn row ->
      Enum.reduce(rename_columns, Map.drop(row, Map.keys(rename_columns)), fn {old, new}, acc ->
        Map.put(acc, new, Map.fetch!(row, old))
      end)
    end)
  end

  @spec drop(Enumerable.t(), [String.t()]) :: Enumerable.t()

  def drop(rows, columns) do
    Stream.map(rows, fn row ->
      Enum.each(columns, &Map.fetch!(row, &1))

      Map.drop(row, columns)
    end)
  end

  @spec take(Enumerable.t(), [String.t()]) :: Enumerable.t()

  def take(rows, candidate_columns) do
    Stream.map(rows, fn row ->
      candidate_columns
      |> Map.new(fn col -> {col, detach(Map.fetch!(row, col))} end)
    end)
  end

  @spec select(Enumerable.t(), %{String.t() => String.t()}) :: Enumerable.t()

  def select(rows, select_columns) do
    rows
    |> take(Map.keys(select_columns))
    |> rename(select_columns)
  end

  @spec blank?(Refract.row()) :: boolean()

  def blank?(row) do
    Enum.all?(row, fn {_col, value} -> Utils.blank?(value) end)
  end

  @spec from(Enumerable.t(), (Refract.row() -> as_boolean(term()))) :: Enumerable.t()

  def from(rows, fun) do
    Stream.drop_while(rows, fn row ->
      not truthy?(fun.(row))
    end)
  end

  @spec until(Enumerable.t(), (Refract.row() -> as_boolean(term()))) :: Enumerable.t()

  def until(rows, fun) do
    Stream.take_while(rows, fn row ->
      not truthy?(fun.(row))
    end)
  end

  @spec pivot(Enumerable.t(), keyword()) :: Enumerable.t()

  def pivot(rows, opts) do
    opts = Keyword.validate!(opts, [:by, :key, :value, :columns])

    by = Keyword.fetch!(opts, :by)
    key = Keyword.fetch!(opts, :key)
    value = Keyword.fetch!(opts, :value)
    columns = Keyword.fetch!(opts, :columns)

    rows
    |> Stream.chunk_by(&Map.fetch!(&1, by))
    |> Stream.map(fn [first | _] = lines ->
      id = Map.fetch!(first, by)
      values = Enum.reduce(lines, %{}, &insert_pivot_value(&1, &2, id, key, value, columns))

      columns
      |> Map.new(fn col -> {col, Map.get(values, col)} end)
      |> Map.put(by, id)
    end)
  end

  # csv parser keeps long values as references to original bin,
  # by copying it we can avoid holding in memory
  defp detach(value) when is_binary(value) do
    if :binary.referenced_byte_size(value) > byte_size(value) do
      :binary.copy(value)
    else
      value
    end
  end

  defp detach(value), do: value

  defp insert_pivot_value(line, values, id, key, value, columns) do
    col = Map.fetch!(line, key)

    cond do
      col not in columns ->
        raise ArgumentError, "key #{inspect(col)} for id #{inspect(id)} is not in columns"

      Map.has_key?(values, col) ->
        raise ArgumentError, "key #{inspect(col)} appears twice for id #{inspect(id)}"

      true ->
        Map.put(values, col, Map.fetch!(line, value))
    end
  end
end
