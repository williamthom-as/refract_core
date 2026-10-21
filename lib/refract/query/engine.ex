defmodule Refract.Query.Engine do
  @moduledoc """
  behaviour for a query engine behind `Refract.Query`. `Refract.Query.DuckDB` is the default.
  """

  @type state :: term()

  @callback open(opts :: keyword()) :: {:ok, state()} | {:error, term()}

  @callback close(state()) :: :ok

  @callback table(
              state(),
              name :: String.t(),
              columns :: [String.t()],
              rows :: Enumerable.t([String.t() | nil])
            ) :: :ok | {:error, term()}

  @callback view(
              state(),
              name :: String.t(),
              glob :: String.t(),
              opts :: [Refract.Query.view_opt()]
            ) :: :ok | {:error, term()}

  @callback run(
              state(),
              sql :: String.t(),
              params :: list()
            ) :: {:ok, columns :: [String.t()], rows :: Enumerable.t()} | {:error, term()}
end
