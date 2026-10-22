defmodule Refract.Reader do
  @moduledoc """
  behaviour for tabular readers. to use, implement `open/2` and return arrays of cells
  `use Refract.Reader` injects `stream/2`, `locate/3`, `classify/3`, `suggest/3` and `load/2`.
  implement `extensions/0` to be picked by file extension in `Refract.Classify.folder/3`.

  options go to `open/2`, bar the names refract keeps for itself, so a reader picks other names:
  - `stream`: `skip`
  - `locate`: `within`, `on_miss`, `header_row`
  - `classify`: `within`, `min_score`, `margin`, `values`, `pick`, `name`
  - `suggest`: `within`, `header_row`
  - `load`: `max_bytes`

  note: you can check/verify a custom reader with `Refract.Test.ReaderCase`

      defmodule MyReader do
        use Refract.Reader

        @impl Refract.Reader
        def open(source, opts), do: {:ok, lines_of_cells}
      end
  """

  @callback open(source :: Refract.source(), opts :: keyword()) ::
              {:ok, Enumerable.t()} | {:error, term()}

  @callback facts(source :: Refract.source(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @callback extensions() :: [String.t()]

  @optional_callbacks facts: 2, extensions: 0

  alias Refract.Reader.Header
  alias Refract.Reader.Lookup

  alias Refract.Classify
  alias Refract.Classify.Facts
  alias Refract.Classify.Score
  alias Refract.Errors.ParseError
  alias Refract.Grid
  alias Refract.Source
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

      @spec classify(Refract.source(), [Refract.Shape.t() | module()], keyword()) ::
              {:ok, Refract.Classify.Result.t()} | {:error, term()}

      def classify(source, shapes, opts \\ []),
        do: Refract.Reader.classify(__MODULE__, source, shapes, opts)

      @spec suggest(Refract.source(), Refract.Shape.t() | module(), keyword()) ::
              {:ok, Refract.Table.Report.Line.t()} | {:error, term()}

      def suggest(source, shape, opts \\ []),
        do: Refract.Reader.suggest(__MODULE__, source, shape, opts)

      @spec load(Refract.source(), keyword()) :: {:ok, Refract.Grid.t()} | {:error, term()}

      def load(source, opts \\ []), do: Refract.Reader.load(__MODULE__, source, opts)
    end
  end

  @spec stream(module(), Refract.source(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}

  def stream(reader, source, opts) do
    {stream_opts, open_opts} = Keyword.split(opts, [:skip])
    skip = Keyword.get(stream_opts, :skip, 0)

    case reader.open(source, open_opts) do
      {:ok, raw} ->
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
    {locate_opts, open_opts} = Keyword.split(opts, [:within, :on_miss, :header_row])
    locate_opts = Locate.validate_opts!(locate_opts)

    case reader.open(source, open_opts) do
      {:ok, raw} -> parse_error_as_error(fn -> Table.locate(raw, spec, locate_opts) end)
      {:error, _reason} = error -> error
    end
  end

  @spec classify(reader :: module(), Refract.source(), [Refract.Shape.t() | module()], keyword()) ::
          {:ok, Classify.Result.t()} | {:error, term()}

  def classify(reader, source, shapes, opts) do
    {classify_opts, open_opts} =
      Keyword.split(opts, [:within, :min_score, :margin, :values, :pick, :name])

    classify_opts =
      classify_opts
      |> Keyword.put_new(:name, Source.name(source))
      |> Score.validate_opts!()

    case reader.open(source, open_opts) do
      {:ok, raw} ->
        parse_error_as_error(fn ->
          {:ok,
           raw
           |> Classify.lines(shapes, classify_opts)
           |> Facts.Source.add(reader, source, open_opts)}
        end)

      {:error, _reason} = error ->
        error
    end
  end

  @spec suggest(reader :: module(), Refract.source(), Refract.Shape.t() | module(), keyword()) ::
          {:ok, Refract.Table.Report.Line.t()} | {:error, term()}

  def suggest(reader, source, shape, opts) do
    {suggest_opts, open_opts} = Keyword.split(opts, [:within, :header_row])

    case reader.open(source, open_opts) do
      {:ok, raw} ->
        parse_error_as_error(fn -> {:ok, Classify.suggest(raw, shape, suggest_opts)} end)

      {:error, _reason} = error ->
        error
    end
  end

  @type reader_entry :: Lookup.reader_entry()

  @spec for_path(Path.t(), [reader_entry()]) ::
          {:ok, {module(), keyword()}} | {:error, {:unsupported, String.t()}}

  def for_path(path, readers \\ []), do: Lookup.for_path(path, readers)

  @spec validate_readers!(term()) :: :ok

  def validate_readers!(readers), do: Lookup.validate!(readers)

  @spec load(reader :: module(), Refract.source(), keyword()) ::
          {:ok, Grid.t()} | {:error, term()}

  def load(reader, source, opts) do
    {grid_opts, open_opts} = Keyword.split(opts, [:max_bytes])

    max_bytes = Keyword.get(grid_opts, :max_bytes, 10_000_000)

    with :ok <- size_check(source, max_bytes, streams_allowed: false),
         {:ok, raw} <- reader.open(source, open_opts) do
      parse_error_as_error(fn -> {:ok, Grid.new(Enum.to_list(raw))} end)
    end
  end

  defp parse_error_as_error(read) do
    read.()
  rescue
    error in ParseError -> {:error, {:parse_error, Exception.message(error)}}
  end
end
