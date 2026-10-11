defmodule Refract.CSV.Facts do
  @moduledoc false

  @spec run(Refract.source(), keyword()) :: {:ok, map()} | {:error, term()}

  def run(_source, _opts), do: {:ok, %{}}

  @spec separator(Refract.source()) :: {:ok, String.t()} | {:error, term()}

  def separator(_source), do: {:ok, ","}
end
