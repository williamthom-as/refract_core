defmodule Refract.Classify.Folder do
  @moduledoc false

  alias Refract.Classify.Result
  alias Refract.Classify.Score
  alias Refract.Reader
  alias Refract.Shape

  @type item :: {Path.t(), {:ok, Result.t()} | {:error, term()}}

  @type opt ::
          Score.opt()
          | {:readers, %{String.t() => Reader.reader_entry()}}
          | {:max_concurrency, pos_integer()}

  @spec run(Path.t(), [Shape.t() | module()], [opt()]) ::
          {:ok, Enumerable.t(item())} | {:error, term()}

  def run(dir, shapes, opts) do
    {classify_opts, folder_opts} =
      Keyword.split(opts, [:within, :min_score, :margin, :values, :pick])

    folder_opts =
      Keyword.validate!(folder_opts, readers: %{}, max_concurrency: System.schedulers_online())

    readers = Keyword.fetch!(folder_opts, :readers)
    max_concurrency = Keyword.fetch!(folder_opts, :max_concurrency)

    Score.validate_opts!(classify_opts)
    Reader.validate_readers!(readers)
    validate_max_concurrency(max_concurrency)

    resolved_shapes = Shape.resolve_all(shapes)

    with {:ok, names} <- File.ls(dir) do
      {:ok,
       names
       |> Enum.sort()
       |> Enum.map(&Path.join(dir, &1))
       |> Enum.filter(&File.regular?/1)
       |> Task.async_stream(&classify_file(&1, readers, resolved_shapes, classify_opts),
         max_concurrency: max_concurrency,
         ordered: true,
         timeout: :infinity
       )
       |> Stream.map(fn {:ok, item} -> item end)}
    end
  end

  defp validate_max_concurrency(max_concurrency)
       when is_integer(max_concurrency) and max_concurrency > 0,
       do: :ok

  defp validate_max_concurrency(max_concurrency) do
    raise ArgumentError,
          "max_concurrency must be a positive integer, got: #{inspect(max_concurrency)}"
  end

  defp classify_file(file, readers, shapes, opts) do
    {file, classify_with(Reader.for_path(file, readers), file, shapes, opts)}
  end

  defp classify_with({:ok, {reader, reader_opts}}, file, shapes, opts),
    do: reader.classify(file, shapes, Keyword.merge(opts, reader_opts))

  defp classify_with({:error, _reason} = error, _file, _shapes, _opts), do: error
end
