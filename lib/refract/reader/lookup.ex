defmodule Refract.Reader.Lookup do
  @moduledoc false

  alias Refract.Source

  import Refract.Utils, only: [exports?: 3]

  @type reader_entry :: module() | {module(), keyword()}

  @spec for_path(Path.t(), [reader_entry()]) ::
          {:ok, {module(), keyword()}} | {:error, {:unsupported, String.t()}}

  def for_path(path, readers) do
    extension = Source.extension(path)

    [Refract.CSV]
    |> by_extension()
    |> Map.merge(by_extension(readers))
    |> Map.fetch(extension)
    |> found(extension)
  end

  @spec validate!(term()) :: :ok

  def validate!(readers) when is_list(readers) do
    readers
    |> Enum.map(&entry/1)
    |> Enum.flat_map(fn {reader, _opts} -> validated_extensions(reader) end)
    |> validate_unique_extensions()
  end

  def validate!(readers) do
    raise ArgumentError, "readers must be a list of readers, got: #{inspect(readers)}"
  end

  defp by_extension(readers) do
    for reader <- readers,
        {module, opts} = entry(reader),
        extension <- module.extensions(),
        into: %{},
        do: {extension, {module, opts}}
  end

  defp found({:ok, entry}, _extension), do: {:ok, entry}
  defp found(:error, extension), do: {:error, {:unsupported, extension}}

  defp entry({reader, opts}) when is_atom(reader) and is_list(opts), do: {reader, opts}
  defp entry(reader) when is_atom(reader), do: {reader, []}

  defp entry(reader) do
    raise ArgumentError, "reader must be a module or {module, opts}, got: #{inspect(reader)}"
  end

  defp validated_extensions(reader) do
    validate_reader_module(reader)

    extensions = reader.extensions()
    Enum.each(extensions, &validate_extension(reader, &1))

    extensions
  end

  defp validate_reader_module(reader) do
    if not exports?(reader, :classify, 3) do
      raise ArgumentError, "reader #{inspect(reader)} must use Refract.Reader"
    end

    if not exports?(reader, :extensions, 0) do
      raise ArgumentError, "reader #{inspect(reader)} must declare its extensions/0"
    end
  end

  defp validate_extension(reader, extension) do
    if not extension?(extension) do
      raise ArgumentError,
            "reader #{inspect(reader)} extension must be lowercase with no dot, got: #{inspect(extension)}"
    end
  end

  defp extension?(extension) when is_binary(extension) do
    extension != "" and extension == String.downcase(extension) and
      not String.contains?(extension, ".")
  end

  defp extension?(_extension), do: false

  defp validate_unique_extensions(extensions) do
    case extensions -- Enum.uniq(extensions) do
      [] -> :ok
      [extension | _] -> raise ArgumentError, "more than one reader claims #{inspect(extension)}"
    end
  end
end
