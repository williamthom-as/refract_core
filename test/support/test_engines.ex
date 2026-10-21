defmodule Refract.TestEngines.Stub do
  @behaviour Refract.Query.Engine

  @impl Refract.Query.Engine
  def open(opts), do: {:ok, %{opts: opts, session: make_ref(), closed: :atomics.new(1, [])}}

  @impl Refract.Query.Engine
  def view(state, name, glob, opts) do
    case Keyword.fetch!(opts, :format) do
      format when format in ["csv", "parquet"] -> call(state, {:view, name, glob, opts})
      format -> {:error, {:unsupported_format, format}}
    end
  end

  @impl Refract.Query.Engine
  def table(state, name, columns, rows),
    do: call(state, {:table, name, columns, Enum.to_list(rows)})

  @impl Refract.Query.Engine
  def run(%{closed: closed, opts: opts} = state, sql, params) do
    with :ok <- call(state, {:run, sql, params}) do
      opts
      |> Keyword.get(:results, %{})
      |> Map.fetch(sql)
      |> result(closed)
    end
  end

  @impl Refract.Query.Engine
  def close(%{closed: closed}), do: :atomics.put(closed, 1, 1)

  defp result({:ok, {columns, rows}}, closed), do: {:ok, columns, guarded(rows, closed)}
  defp result(:error, _closed), do: {:error, {:query_error, "no result for this sql"}}

  defp guarded(rows, closed) do
    Stream.map(rows, fn row ->
      if :atomics.get(closed, 1) == 1 do
        raise Refract.Errors.QueryError, message: "query is closed"
      end

      row
    end)
  end

  defp call(%{closed: closed, opts: opts}, message) do
    if :atomics.get(closed, 1) == 1 do
      {:error, :closed}
    else
      opts |> Keyword.get(:notify, self()) |> send(message)
      :ok
    end
  end
end

defmodule Refract.TestEngines.Refusing do
  @behaviour Refract.Query.Engine

  @impl Refract.Query.Engine
  def open(_opts), do: {:error, :refused}

  @impl Refract.Query.Engine
  def view(_state, _name, _glob, _opts), do: {:error, :refused}

  @impl Refract.Query.Engine
  def table(_state, _name, _columns, _rows), do: {:error, :refused}

  @impl Refract.Query.Engine
  def run(_state, _sql, _params), do: {:error, :refused}

  @impl Refract.Query.Engine
  def close(_state), do: :ok
end
