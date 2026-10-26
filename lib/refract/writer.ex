defmodule Refract.Writer do
  @moduledoc """
  behaviour for writers, implement `encode/2` and `extension/0` to make use of.
  `use Refract.Writer` injects `write/3` and `write_chunks/3`. `cells/2` turns row maps into a
  header line then each row's values in header order, for writers of lines of cells.

  note: you can check/verify a custom writer with `Refract.Test.WriterCase`

      {:ok, paths} = Refract.CSV.write_chunks(rows, "out", prefix: "bills", rows_per_file: 10_000)
  """

  @callback encode(rows :: Enumerable.t(), opts :: keyword()) :: Enumerable.t()

  @callback extension() :: String.t()

  @type write_chunks_opt ::
          {:prefix, String.t()}
          | {:rows_per_file, pos_integer()}
          | {:header, [String.t()]}

  defmacro __using__(_opts) do
    quote do
      @behaviour Refract.Writer

      @spec write(Enumerable.t(), Path.t(), keyword()) :: :ok | {:error, term()}

      def write(rows, path, opts \\ []), do: Refract.Writer.write(__MODULE__, rows, path, opts)

      @spec write_chunks(Enumerable.t(), Path.t(), [Refract.Writer.write_chunks_opt()]) ::
              {:ok, [Path.t()]} | {:error, File.posix()}

      def write_chunks(rows, path, opts \\ []),
        do: Refract.Writer.write_chunks(__MODULE__, rows, path, opts)
    end
  end

  @write_buffer_size 1_000

  @spec cells(Enumerable.t(), [String.t()] | nil) :: Enumerable.t()

  def cells(rows, nil) do
    Stream.transform(rows, nil, fn
      row, nil ->
        header = row |> Map.keys() |> Enum.sort()

        {[header, values(row, header)], header}

      row, header ->
        {[values(row, header)], header}
    end)
  end

  def cells(rows, header), do: Stream.concat([header], Stream.map(rows, &values(&1, header)))

  defp values(row, header), do: Enum.map(header, &Map.fetch!(row, &1))

  @spec write(module(), Enumerable.t(), Path.t(), keyword()) :: :ok | {:error, term()}

  def write(writer, rows, path, opts) do
    tmp = "#{path}.#{System.unique_integer([:positive])}.tmp"

    with {:ok, file} <- File.open(tmp, [:write, :binary]) do
      try do
        rows
        |> writer.encode(opts)
        |> Stream.chunk_every(@write_buffer_size)
        |> Enum.each(&IO.binwrite(file, &1))
      rescue
        e ->
          File.close(file)
          File.rm(tmp)

          reraise e, __STACKTRACE__
      end

      publish(file, tmp, path)
    end
  end

  defp publish(file, tmp, path) do
    with :ok <- File.close(file),
         :ok <- File.rename(tmp, path) do
      :ok
    else
      {:error, _reason} = error ->
        File.rm(tmp)

        error
    end
  end

  @spec write_chunks(module(), Enumerable.t(), Path.t(), [write_chunks_opt()]) ::
          {:ok, [Path.t()]} | {:error, File.posix()}

  def write_chunks(writer, rows, path, opts \\ []) do
    opts = Keyword.validate!(opts, [:prefix, :rows_per_file, :header])

    prefix = Keyword.fetch!(opts, :prefix)
    rows_per_file = Keyword.fetch!(opts, :rows_per_file)
    write_opts = Keyword.take(opts, [:header])

    validate_rows_per_file(rows_per_file)

    rows
    |> Stream.chunk_every(rows_per_file)
    |> Stream.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {chunk, index}, {:ok, paths} ->
      file_path =
        Path.join(
          path,
          generate_file_path(prefix, index, writer.extension())
        )

      case write(writer, chunk, file_path, write_opts) do
        :ok -> {:cont, {:ok, [file_path | paths]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, paths} -> {:ok, Enum.reverse(paths)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp generate_file_path(prefix, index, extension) do
    "#{prefix}_#{index}.#{extension}"
  end

  defp validate_rows_per_file(rows_per_file) when is_integer(rows_per_file) and rows_per_file > 0,
    do: :ok

  defp validate_rows_per_file(val),
    do: raise(ArgumentError, "rows_per_file must be a positive integer, got: #{inspect(val)}")
end
