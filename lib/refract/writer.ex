defmodule Refract.Writer do
  @callback encode(rows :: Enumerable.t(), opts :: keyword()) :: Enumerable.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour Refract.Writer

      @spec write(Enumerable.t(), Path.t(), keyword()) :: :ok | {:error, term()}

      def write(rows, path, opts \\ []), do: Refract.Writer.write(__MODULE__, rows, path, opts)
    end
  end

  @spec write(module(), Enumerable.t(), Path.t(), keyword()) :: :ok | {:error, term()}

  @write_buffer_size 1_000

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

      File.close(file)
      File.rename(tmp, path)
    end
  end
end
