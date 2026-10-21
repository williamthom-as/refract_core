defmodule Refract.TestEngines.Stub do
  @behaviour Refract.Query.Engine

  @impl Refract.Query.Engine
  def open(opts), do: {:ok, %{opts: opts, session: make_ref(), closed: :atomics.new(1, [])}}

  @impl Refract.Query.Engine
  def view(state, name, glob, opts), do: call(state, {:view, name, glob, opts})

  @impl Refract.Query.Engine
  def table(state, name, columns, rows),
    do: call(state, {:table, name, columns, Enum.to_list(rows)})

  @impl Refract.Query.Engine
  def close(%{closed: closed}), do: :atomics.put(closed, 1, 1)

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
  def close(_state), do: :ok
end
