defmodule Refract.KeyProvider do
  @callback fetch(opts :: keyword()) :: {:ok, %{pos_integer() => binary()}} | {:error, term()}
end
