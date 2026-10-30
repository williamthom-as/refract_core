defmodule Refract.Query do
  @moduledoc """
  sql over folders and tables of data, run by an engine passed as `engine:`

  engines are plugins, use an existing or implement your own
  `Refract.Query.Engine`.

  note doesnt use genserver for state, change if needed.
  """

  alias Refract.Query.Result
  alias Refract.Table

  import Refract.String.Utils, only: [text: 1]
  import Refract.Utils, only: [exports?: 3]

  @enforce_keys [:engine, :state]

  defstruct [:engine, :state]

  @type t :: %__MODULE__{engine: module(), state: term()}

  @type types :: :text | :infer

  @type open_opt :: {:engine, module()} | {atom(), term()}

  @type view_opt :: {:types, types()} | {:format, String.t()}

  @type table_opt :: {:columns, [String.t()]}

  @spec open([open_opt()]) :: {:ok, t()} | {:error, term()}

  def open(opts \\ []) do
    {opts, engine_opts} = Keyword.split(opts, [:engine])
    engine = Keyword.fetch!(opts, :engine)

    validate_engine(engine)

    with {:ok, state} <- engine.open(engine_opts) do
      {:ok, %__MODULE__{engine: engine, state: state}}
    end
  end

  @spec open!([open_opt()]) :: t()

  def open!(opts \\ []) do
    case open(opts) do
      {:ok, query} -> query
      {:error, reason} -> raise ArgumentError, "cannot open query capability: #{inspect(reason)}"
    end
  end

  @spec close(t()) :: :ok | {:error, term()}

  def close(%__MODULE__{engine: engine, state: state}) do
    engine.close(state)
  end

  @spec close!(t()) :: :ok

  def close!(query) do
    case close(query) do
      :ok -> :ok
      {:error, reason} -> raise ArgumentError, "cannot close query capability: #{inspect(reason)}"
    end
  end

  @spec view(t(), name :: String.t(), glob :: String.t(), opts :: [view_opt()]) ::
          :ok | {:error, term()}

  def view(%__MODULE__{engine: engine, state: state}, name, glob, opts \\ []) do
    opts = validate_view_opts!(opts)

    validate_name(name)

    engine.view(state, name, glob, opts)
  end

  @spec views(t(), dir :: Path.t(), opts :: [view_opt()]) ::
          {:ok, [String.t()]} | {:error, term()}

  def views(%__MODULE__{} = query, dir, opts \\ []) do
    opts = validate_view_opts!(opts)
    format = Keyword.fetch!(opts, :format)

    with {:ok, entries} <- File.ls(dir) do
      entries
      |> Enum.sort()
      |> Enum.reject(&String.starts_with?(&1, "_"))
      |> Enum.filter(&holds_format?(Path.join(dir, &1), format))
      |> Enum.reduce_while({:ok, []}, &add_view(&1, &2, query, dir, opts))
      |> in_order()
    end
  end

  defp validate_view_opts!(opts) do
    opts = Keyword.validate!(opts, types: :text, format: "csv")

    validate_types(Keyword.fetch!(opts, :types))
    validate_format(Keyword.fetch!(opts, :format))

    opts
  end

  defp holds_format?(path, format) do
    case File.ls(path) do
      {:ok, files} -> Enum.any?(files, &String.ends_with?(&1, "." <> format))
      {:error, _reason} -> false
    end
  end

  defp add_view(name, {:ok, names}, query, dir, opts) do
    glob = Path.join([dir, name, "*." <> Keyword.fetch!(opts, :format)])

    case view(query, name, glob, opts) do
      :ok -> {:cont, {:ok, [name | names]}}
      error -> {:halt, error}
    end
  end

  defp in_order({:ok, names}), do: {:ok, Enum.reverse(names)}
  defp in_order(error), do: error

  @spec table(t(), name :: String.t(), Table.t() | Enumerable.t(), opts :: [table_opt()]) ::
          :ok | {:error, term()}

  def table(query, name, rows, opts \\ [])

  def table(query, name, %Table{header: header, rows: rows}, opts) do
    opts = Keyword.validate!(opts, columns: header)

    create_table(query, name, Keyword.fetch!(opts, :columns), rows)
  end

  def table(query, name, rows, opts) do
    opts = Keyword.validate!(opts, [:columns])

    create_table(query, name, Keyword.fetch!(opts, :columns), rows)
  end

  defp create_table(%__MODULE__{engine: engine, state: state}, name, columns, rows) do
    validate_name(name)
    validate_columns(columns)

    engine.table(state, name, columns, Stream.map(rows, &cells(&1, columns)))
  end

  defp cells(row, columns), do: Enum.map(columns, &text(Map.get(row, &1)))

  @spec run(t(), sql :: String.t(), params :: list()) ::
          {:ok, Result.t()} | {:error, term()}

  def run(%__MODULE__{engine: engine, state: state}, sql, params \\ []) do
    validate_sql(sql)
    validate_params(params)

    with {:ok, columns, rows} <- engine.run(state, sql, params),
         :ok <- unique_columns(columns) do
      {:ok, %Result{columns: columns, rows: Stream.map(rows, &Map.new(Enum.zip(columns, &1)))}}
    end
  end

  @spec run!(t(), sql :: String.t(), params :: list()) :: Result.t()

  def run!(query, sql, params \\ []) do
    case run(query, sql, params) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, "cannot run query: #{inspect(reason)}"
    end
  end

  defp unique_columns(columns) do
    case Enum.uniq(columns -- Enum.uniq(columns)) do
      [] -> :ok
      duplicates -> {:error, {:duplicate_columns, duplicates}}
    end
  end

  defp validate_sql(sql) when is_binary(sql), do: :ok

  defp validate_sql(sql) do
    raise ArgumentError, "sql must be a string, got: #{inspect(sql)}"
  end

  defp validate_params(params) when is_list(params), do: :ok

  defp validate_params(params) do
    raise ArgumentError, "params must be a list, got: #{inspect(params)}"
  end

  defp validate_engine(engine) do
    if not exports?(engine, :open, 1) do
      raise ArgumentError,
            "engine must implement Refract.Query.Engine, got: #{inspect(engine)}"
    end
  end

  defp validate_types(types) when types in [:text, :infer], do: :ok

  defp validate_types(types) do
    raise ArgumentError, "types must be :text or :infer, got: #{inspect(types)}"
  end

  defp validate_format(format) when is_binary(format) do
    if not Regex.match?(~r/^[a-z0-9]+$/, format) do
      raise ArgumentError,
            "format must be a lowercase file extension with no dot, got: #{inspect(format)}"
    end
  end

  defp validate_format(format) do
    raise ArgumentError, "format must be a string, got: #{inspect(format)}"
  end

  defp validate_columns([_ | _] = columns) do
    if not Enum.all?(columns, &is_binary/1) do
      raise ArgumentError, "columns must be strings, got: #{inspect(columns)}"
    end
  end

  defp validate_columns(columns) do
    raise ArgumentError, "columns must be a non empty list of strings, got: #{inspect(columns)}"
  end

  defp validate_name(name) when is_binary(name) do
    if not Regex.match?(~r/^[a-z][a-z0-9_]*$/, name) do
      raise ArgumentError, "name must match [a-z][a-z0-9_]*, got: #{inspect(name)}"
    end
  end

  defp validate_name(name) do
    raise ArgumentError, "name must be a string, got: #{inspect(name)}"
  end
end
