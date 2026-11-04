defmodule Refract.Writer.Lookup do
  @moduledoc false

  alias Refract.Source

  @spec for_path(Path.t(), [module()]) :: {:ok, module()} | {:error, {:unsupported, String.t()}}

  def for_path(path, writers) do
    extension = Source.extension(path)

    [Refract.CSV | writers]
    |> Map.new(&{&1.extension(), &1})
    |> Map.fetch(extension)
    |> case do
      {:ok, writer} -> {:ok, writer}
      :error -> {:error, {:unsupported, extension}}
    end
  end
end
