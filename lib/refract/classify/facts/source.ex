defmodule Refract.Classify.Facts.Source do
  @moduledoc false

  alias Refract.Classify.Facts
  alias Refract.Classify.Result

  import Refract.Source, only: [path: 1, size: 1]
  import Refract.Utils, only: [exports?: 3]

  @spec add(Result.t(), module(), Refract.source(), keyword()) :: Result.t()

  def add(%Result{file: %Facts{} = facts} = result, reader, source, opts) do
    %{
      result
      | file: %Facts{
          facts
          | path: path(source),
            size: size_or_unknown(size(source)),
            format: format(reader, source, opts)
        }
    }
  end

  defp size_or_unknown({:ok, size}), do: size
  defp size_or_unknown({:error, _reason}), do: :unknown

  defp format(_reader, {:stream, _chunks}, _opts), do: %{}

  defp format(reader, source, opts),
    do: reader |> exports?(:facts, 2) |> format(reader, source, opts)

  defp format(true, reader, source, opts), do: reader_format(reader.facts(source, opts))
  defp format(false, _reader, _source, _opts), do: %{}

  defp reader_format({:ok, format}), do: format
  defp reader_format({:error, _reason}), do: %{}
end
