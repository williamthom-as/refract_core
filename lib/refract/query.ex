defmodule Refract.Query do
  @moduledoc """
  sql over folders and tables of data, run by an engine passed as `engine:`

  engines are plugins (eg `Refract.Query.DuckDB` from `refract_duckdb`),
  or implement your own `Refract.Query.Engine`.

  note doesnt use genserver for state, change if needed.
  """

  defstruct [:engine, :state]

  @type t :: %__MODULE__{engine: module(), state: term()}

  @spec open(keyword()) :: {:ok, t()} | {:error, term()}

  def open(opts \\ []) do
    opts = Keyword.validate!(opts, [:engine])
    engine = Keyword.fetch!(opts, :engine)

    validate_engine(engine)

    with {:ok, state} <- engine.open(Keyword.delete(opts, :engine)) do
      {:ok, %__MODULE__{engine: engine, state: state}}
    end
  end

  @spec open!(keyword()) :: t()

  def open!(opts \\ []) do
    case open(opts) do
      {:ok, query} -> query
      {:error, reason} -> raise ArgumentError, "cannot open query capability: #{inspect(reason)}"
    end
  end

  defp validate_engine(engine) do
    if not (is_atom(engine) and Code.ensure_loaded?(engine) and
              function_exported?(engine, :open, 1)) do
      raise ArgumentError,
            "engine must implement Refract.Query.Engine, got: #{inspect(engine)}"
    end
  end
end
