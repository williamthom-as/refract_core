defmodule Refract.Query.Engine do
  @moduledoc """
  behaviour for a query engine behind `Refract.Query`. `Refract.Query.DuckDB` is the default.
  """

  @callback open(opts :: keyword()) :: {:ok, state :: term()} | {:error, term()}
end
