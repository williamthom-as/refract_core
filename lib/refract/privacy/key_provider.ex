defmodule Refract.Privacy.KeyProvider do
  @moduledoc """

  behaviour for fetching root keys from a provider. current impl is
  just `Env`, which fetches from env vars.

  returns `%{version => root}`, used by `Keyring.from_provider!/3`
  """

  @callback fetch(opts :: keyword()) :: {:ok, %{pos_integer() => binary()}} | {:error, term()}
end
