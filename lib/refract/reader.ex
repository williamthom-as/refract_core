defmodule Refract.Reader do
  @moduledoc """
  behaviour for tabular readers. to use, implement `open/2` and return arrays of cells
  `use Refract.Reader` injects `stream/2`, `locate/3`, `classify/3`, `suggest/3`, `profile/3`,
  `validate/3`, `fields/3` and `load/2`.
  implement `extensions/0` to be picked by file extension in `Refract.Classify.folder/3`.

  options go to `open/2`, bar the names refract keeps for itself, so a reader picks other names:
  - `stream`: `skip`
  - `locate`: `within`, `on_miss`, `header_row`
  - `classify`: `within`, `min_score`, `margin`, `values`, `pick`, `name`
  - `suggest`: `within`, `header_row`
  - `profile`: `within`, `header_row`, `except`, `max_distinct`, `max_lines`, `values`,
    `fuzzy`, `columns`
  - `validate`: `within`, `header_row`, `values` (and `max_bytes` when the shape has fields or
    document rules, as the whole file is read)
  - `load`, `fields`: `max_bytes`

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
  alias Refract.Profile
  alias Refract.Profile.Count
  alias Refract.Shape
  alias Refract.Source
  alias Refract.Table
  alias Refract.Table.Locate
  alias Refract.Table.Spec
  alias Refract.Validate
  alias Refract.Validate.Rules

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

      @spec profile(Refract.source(), Refract.Shape.t() | module(), keyword()) ::
              {:ok, Refract.Profile.Result.t()} | {:error, term()}

      def profile(source, shape, opts \\ []),
        do: Refract.Reader.profile(__MODULE__, source, shape, opts)

      @spec validate(Refract.source(), Refract.Shape.t() | module(), keyword()) ::
              {:ok, Refract.Validate.Result.t()} | {:error, term()}

      def validate(source, shape, opts \\ []),
        do: Refract.Reader.validate(__MODULE__, source, shape, opts)

      @spec fields(Refract.source(), Refract.Shape.t() | module(), keyword()) ::
              {:ok, %{String.t() => Refract.cell()}} | {:error, term()}

      def fields(source, shape, opts \\ []),
        do: Refract.Reader.fields(__MODULE__, source, shape, opts)

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
    {locate_opts, open_opts} = Keyword.split(opts, Keyword.keys(Locate.options()))
    locate_opts = Locate.validate_opts!(locate_opts)

    read(reader, source, open_opts, &Table.locate(&1, spec, locate_opts))
  end

  @spec classify(reader :: module(), Refract.source(), [Refract.Shape.t() | module()], keyword()) ::
          {:ok, Classify.Result.t()} | {:error, term()}

  def classify(reader, source, shapes, opts) do
    {classify_opts, open_opts} = Keyword.split(opts, Keyword.keys(Score.options()))

    classify_opts =
      classify_opts
      |> Keyword.put_new(:name, Source.name(source))
      |> Score.validate_opts!()

    read(reader, source, open_opts, fn raw ->
      result =
        raw
        |> Classify.lines(shapes, classify_opts)
        |> Facts.Source.add(reader, source, open_opts)

      {:ok, %{result | reader: {reader, open_opts}}}
    end)
  end

  @spec suggest(reader :: module(), Refract.source(), Refract.Shape.t() | module(), keyword()) ::
          {:ok, Refract.Table.Report.Line.t()} | {:error, term()}

  def suggest(reader, source, shape, opts) do
    {suggest_opts, open_opts} = Keyword.split(opts, Keyword.keys(Locate.header_options()))

    read(reader, source, open_opts, &{:ok, Classify.suggest(&1, shape, suggest_opts)})
  end

  @spec profile(reader :: module(), Refract.source(), Refract.Shape.t() | module(), keyword()) ::
          {:ok, Refract.Profile.Result.t()} | {:error, term()}

  def profile(reader, source, shape, opts) do
    {profile_opts, open_opts} =
      Keyword.split(opts, Keyword.keys(Locate.header_options() ++ Count.options()))

    read(reader, source, open_opts, &Profile.lines(&1, shape, profile_opts))
  end

  @spec validate(reader :: module(), Refract.source(), Refract.Shape.t() | module(), keyword()) ::
          {:ok, Refract.Validate.Result.t()} | {:error, term()}

  def validate(reader, source, shape, opts) do
    {validate_opts, read_opts} =
      Keyword.split(opts, Keyword.keys(Locate.header_options() ++ Validate.options()))

    shape
    |> Shape.resolve()
    |> validate_with(reader, source, validate_opts, read_opts)
  end

  defp validate_with(
         %Refract.Shape{fields: fields, validation: %Rules{document: document}} = shape,
         reader,
         source,
         validate_opts,
         open_opts
       )
       when map_size(fields) == 0 and document == [] do
    read(reader, source, open_opts, &Validate.source(&1, shape, validate_opts))
  end

  defp validate_with(shape, reader, source, validate_opts, load_opts) do
    with {:ok, grid} <- load(reader, source, load_opts),
         do: Grid.validate(grid, shape, validate_opts)
  end

  @spec fields(reader :: module(), Refract.source(), Refract.Shape.t() | module(), keyword()) ::
          {:ok, %{String.t() => Refract.cell()}} | {:error, term()}

  def fields(reader, source, shape, opts) do
    with {:ok, grid} <- load(reader, source, opts), do: {:ok, Grid.fields(grid, shape)}
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

    with :ok <- source |> Source.size() |> within_size(source, max_bytes),
         do: read(reader, source, open_opts, &{:ok, Grid.new(&1)})
  end

  @doc false
  @spec read(module(), Refract.source(), keyword(), (Enumerable.t() -> result)) ::
          result | {:error, term()}
        when result: term()

  def read(reader, source, open_opts, fun) do
    with {:ok, raw} <- reader.open(source, open_opts),
         do: parse_error_as_error(fn -> fun.(raw) end)
  end

  defp within_size({:ok, :unknown}, source, _max_bytes),
    do: {:error, {:stream_not_allowed, source}}

  defp within_size({:ok, size}, _source, max_bytes) when size <= max_bytes, do: :ok

  defp within_size({:ok, _size}, _source, max_bytes),
    do: {:error, {:max_bytes_exceeded, max_bytes}}

  defp within_size({:error, _reason} = error, _source, _max_bytes), do: error

  defp parse_error_as_error(read) do
    read.()
  rescue
    error in ParseError -> {:error, {:parse_error, Exception.message(error)}}
  end
end
