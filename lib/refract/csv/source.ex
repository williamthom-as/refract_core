defmodule Refract.CSV.Source do
  @spec open(Refract.source(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}

  def open({:string, content}, _opts), do: {:ok, [content]}

  def open({:stream, lines}, _opts) do
    {:ok, lines}
  end

  def open(path, _opts) when is_binary(path) do
    case File.open(path) do
      {:ok, file} ->
        # pref File.open/close over .exists? for better io errors
        File.close(file)

        {:ok, File.stream!(path)}

      {:error, _reason} = error ->
        error
    end
  end

  def open(source, _opts) do
    {:error, {:unsupported_source, source}}
  end

  @spec strip_bom(Enumerable.t()) :: Enumerable.t()

  def strip_bom(stream) do
    Stream.transform(stream, true, fn
      line, true ->
        stripped = String.replace_prefix(line, "\uFEFF", "")
        {[stripped], false}

      line, false ->
        {[line], false}
    end)
  end
end
