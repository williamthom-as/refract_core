defmodule Refract.Reader do
  @moduledoc """
  behaviour for tabular readers. to use, implement `open/2` and return arrays of cells
  `use Refract.Reader` injects `stream/2`, `locate/3` and `load/2`.

  note: you can check/verify a custom reader with `Refract.Test.ReaderCase`

      defmodule MyReader do
        use Refract.Reader

        @impl Refract.Reader
        def open(source, opts), do: {:ok, lines_of_cells}
      end
  """

  @callback open(source :: Refract.source(), opts :: keyword()) ::
              {:ok, Enumerable.t()} | {:error, term()}

  alias Refract.Reader.Header

  alias Refract.Grid
  alias Refract.Table
  alias Refract.Table.Locate
  alias Refract.Table.Spec

  import Refract.File.Utils, only: [size_check: 3]

  defmacro __using__(_opts) do
    quote do
      @behaviour Refract.Reader

      @spec stream(Refract.source(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}

      def stream(source, opts \\ []), do: Refract.Reader.stream(__MODULE__, source, opts)

      @spec locate(Refract.source(), Refract.Table.Spec.t(), keyword()) ::
              {:ok, Refract.Table.t()} | {:error, term()}

      def locate(source, spec, opts \\ []),
        do: Refract.Reader.locate(__MODULE__, source, spec, opts)

      @spec load(Refract.source(), keyword()) :: {:ok, Refract.Grid.t()} | {:error, term()}

      def load(source, opts \\ []), do: Refract.Reader.load(__MODULE__, source, opts)
    end
  end

  @spec stream(module(), Refract.source(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}

  def stream(reader, source, opts) do
    case reader.open(source, opts) do
      {:ok, raw} ->
        skip = Keyword.get(opts, :skip, 0)
        content = Stream.drop(raw, skip)

        {:ok,
         Stream.transform(content, nil, fn
           row, nil ->
             {[], Header.normalise(row)}

           row, header ->
             {[Header.to_row(header, row)], header}
         end)}

      {:error, _reason} = error ->
        error
    end
  end

  @spec locate(reader :: module(), Refract.source(), Spec.t(), keyword()) ::
          {:ok, Table.t()}
          | {:error, {:header_not_found, Locate.header_miss()}}
          | {:error, term()}

  def locate(reader, source, %Spec{} = spec, opts) do
    {locate_opts, open_opts} = Keyword.split(opts, [:within, :on_miss])
    locate_opts = Locate.validate_opts!(locate_opts)

    case reader.open(source, open_opts) do
      {:ok, raw} -> Table.locate(raw, spec, locate_opts)
      {:error, _reason} = error -> error
    end
  end

  @spec load(reader :: module(), Refract.source(), keyword()) ::
          {:ok, Grid.t()} | {:error, term()}

  def load(reader, source, opts) do
    {grid_opts, open_opts} = Keyword.split(opts, [:max_bytes])

    max_bytes = Keyword.get(grid_opts, :max_bytes, 10_000_000)

    with :ok <- size_check(source, max_bytes, streams_allowed: false),
         {:ok, raw} <- reader.open(source, open_opts),
         rows <- Enum.to_list(raw) do
      {:ok, Grid.new(rows)}
    end
  end
end
