defmodule Refract.Classify.Facts.Source do
  @moduledoc false

  alias Refract.Classify.Facts
  alias Refract.Classify.Result

  import Refract.File.Utils, only: [size: 1]

  @spec add(Result.t(), module(), Refract.source(), keyword()) :: Result.t()

  def add(%Result{file: %Facts{} = facts} = result, reader, source, opts) do
    {:ok, size} = size(source)

    %{
      result
      | file: %Facts{facts | path: path(source), size: size, format: format(reader, source, opts)}
    }
  end

  defp path(path) when is_binary(path), do: path
  defp path(_source), do: nil

  defp format(_reader, {:stream, _chunks}, _opts), do: %{}

  defp format(reader, source, opts) do
    if Code.ensure_loaded?(reader) and function_exported?(reader, :facts, 2) do
      reader_format(reader.facts(source, opts))
    else
      %{}
    end
  end

  defp reader_format({:ok, format}), do: format
  defp reader_format({:error, _reason}), do: %{}
end
