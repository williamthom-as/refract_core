defmodule Refract.Rows do
  @moduledoc """
  all functions over a stream of row maps. all are lazily evaluated, so chain them together.
  unknown columns raises. `update` can take either a function operating on the value, or a
  function provided both the value and a `Refract.Rows.Ctx`(holds row and operated on column
  name).
  `group` folds lines of one id val into a row with a function, `pivot` is the key/value special
  case of it. both need the lines for one id val next to each other. `parallel` runs a pipeline on
  chunks across cores for perf gains

      rows
      |> Refract.Rows.rename(%{"col_0" => "date"})
      |> Refract.Rows.update("cost", &Refract.Parse.number!/1)
      |> Refract.Rows.put("year", &(&1["date"] |> String.split(" ") |> List.last()))
      |> Refract.Rows.drop_blank()
  """

  import Refract.Utils, only: [truthy?: 1]

  alias Refract.String.Utils

  alias Refract.Rows.Ctx

  @spec update(
          Enumerable.t(),
          String.t() | [String.t()],
          (Refract.cell() -> Refract.cell()) | (Refract.cell(), Ctx.t() -> Refract.cell()),
          keyword()
        ) :: Enumerable.t()

  def update(rows, column, fun, opts \\ []) do
    skip_blank = Keyword.get(opts, :skip_blank, false)
    columns = List.wrap(column)

    validate_fun(fun)

    Stream.map(rows, fn row ->
      Enum.reduce(columns, row, fn col, acc ->
        value = Map.fetch!(row, col)

        if skip_blank and Utils.blank?(value) do
          acc
        else
          ctx = Ctx.new(row, col)
          result = call(fun, value, ctx)

          Map.put(acc, col, result)
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

  @spec blank?(Refract.row(), String.t() | [String.t()]) :: boolean()

  def blank?(row, column) do
    column
    |> List.wrap()
    |> Enum.all?(fn col -> row |> Map.fetch!(col) |> Utils.blank?() end)
  end

  @spec drop_blank(Enumerable.t()) :: Enumerable.t()

  def drop_blank(rows), do: Stream.reject(rows, &blank?/1)

  @spec drop_blank(Enumerable.t(), String.t() | [String.t()]) :: Enumerable.t()

  def drop_blank(rows, column), do: Stream.reject(rows, &blank?(&1, column))

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

  @spec group(Enumerable.t(), keyword()) :: Enumerable.t()

  def group(rows, opts) do
    opts = Keyword.validate!(opts, [:by, :into])

    by = Keyword.fetch!(opts, :by)
    into = Keyword.fetch!(opts, :into)

    validate_into(into)

    rows
    |> Stream.chunk_by(&Map.fetch!(&1, by))
    |> Stream.map(fn [first | _] = lines ->
      id = Map.fetch!(first, by)

      lines
      |> into.()
      |> validate_grouped(id)
      |> Map.put(by, id)
    end)
  end

  @spec pivot(Enumerable.t(), keyword()) :: Enumerable.t()

  def pivot(rows, opts) do
    opts = Keyword.validate!(opts, [:by, :key, :value, :columns])

    by = Keyword.fetch!(opts, :by)
    key = Keyword.fetch!(opts, :key)
    value = Keyword.fetch!(opts, :value)
    columns = Keyword.fetch!(opts, :columns)

    group(rows,
      by: by,
      into: fn [first | _] = lines ->
        id = Map.fetch!(first, by)
        values = Enum.reduce(lines, %{}, &insert_pivot_value(&1, &2, id, key, value, columns))

        Map.new(columns, fn col -> {col, Map.get(values, col)} end)
      end
    )
  end

  @spec parallel(Enumerable.t(), (Enumerable.t() -> Enumerable.t()), keyword()) :: Enumerable.t()

  def parallel(rows, fun, opts \\ []) do
    opts = Keyword.validate!(opts, chunk: 1_000, max_concurrency: System.schedulers_online())

    chunk = Keyword.fetch!(opts, :chunk)
    max_concurrency = Keyword.fetch!(opts, :max_concurrency)

    validate_positive(chunk, :chunk)
    validate_positive(max_concurrency, :max_concurrency)

    rows
    |> Stream.chunk_every(chunk)
    |> Task.async_stream(&run_chunk(&1, fun),
      max_concurrency: max_concurrency,
      ordered: true,
      timeout: :infinity
    )
    |> Stream.flat_map(&chunk_rows/1)
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

  defp validate_into(fun) when is_function(fun, 1), do: :ok

  defp validate_into(fun),
    do: raise(ArgumentError, "into must be a function of the lines, got: #{inspect(fun)}")

  defp validate_grouped(row, _id) when is_map(row), do: row

  defp validate_grouped(other, id),
    do:
      raise(
        ArgumentError,
        "into must return a row map for id #{inspect(id)}, got: #{inspect(other)}"
      )

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

  defp call(fun, value, _ctx) when is_function(fun, 1), do: fun.(value)

  defp call(fun, value, ctx) when is_function(fun, 2), do: fun.(value, ctx)

  defp validate_fun(fun) when is_function(fun, 1) or is_function(fun, 2), do: :ok

  defp validate_fun(fun),
    do: raise(ArgumentError, "function #{inspect(fun)} must accept 1 or 2 arguments")

  defp run_chunk(chunk, fun) do
    {:ok, chunk |> fun.() |> Enum.to_list()}
  rescue
    exception -> {:error, exception, __STACKTRACE__}
  end

  defp chunk_rows({:ok, {:ok, rows}}), do: rows
  defp chunk_rows({:ok, {:error, exception, stacktrace}}), do: reraise(exception, stacktrace)

  defp validate_positive(value, _name) when is_integer(value) and value > 0, do: :ok

  defp validate_positive(value, name) do
    raise ArgumentError, "#{name} must be a positive integer, got: #{inspect(value)}"
  end
end
