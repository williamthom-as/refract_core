defmodule Refract.Golden do
  @root Path.expand("../fixtures/golden", __DIR__)

  @spec path(String.t(), String.t()) :: Path.t()

  def path(name, file), do: Path.join([@root, name, file])

  @spec expected(String.t()) :: binary()

  def expected(name), do: File.read!(path(name, "expected.csv"))
end
