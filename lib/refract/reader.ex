defmodule Refract.Reader do
  @moduledoc """
  behaviour for tabular readers. to use, implement `open/2` and return arrays of cells
  `use Refract.Reader` injects `stream/2`, `locate/3`, `classify/3` and `load/2`.

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

  @optional_callbacks facts: 2

  alias Refract.Reader.Header

  alias Refract.Classify
  alias Refract.Classify.Facts
  alias Refract.Classify.Score
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

      @spec load(Refract.source(), keyword()) :: {:ok, Refract.Grid.t()} | {:error, term()}

      def load(source, opts \\ []), do: Refract.Reader.load(__MODULE__, source, opts)

      defoverridable classify: 2, classify: 3
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
        {:ok,
         raw
         |> Classify.lines(shapes, classify_opts)
         |> Facts.Source.add(reader, source, open_opts)}

      {:error, _reason} = error ->
        error
    end
  end

  @type reader_entry :: module() | {module(), keyword()}

  @spec for_path(Path.t(), %{String.t() => reader_entry()}) ::
          {:ok, {module(), keyword()}} | {:error, {:unsupported, String.t()}}

  def for_path(path, readers \\ %{}) do
    extension = Source.extension(path)

    %{"csv" => Refract.CSV, "tsv" => {Refract.CSV, separator: "\t"}}
    |> Map.merge(readers)
    |> Map.fetch(extension)
    |> reader_entry(extension)
  end

  @spec validate_readers!(term()) :: :ok

  def validate_readers!(readers) when is_map(readers), do: Enum.each(readers, &validate_reader/1)

  def validate_readers!(readers) do
    raise ArgumentError, "readers must be a map of extension to reader, got: #{inspect(readers)}"
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

  defp reader_entry({:ok, {reader, opts}}, _extension), do: {:ok, {reader, opts}}

  defp reader_entry({:ok, reader}, _extension), do: {:ok, {reader, []}}

  defp reader_entry(:error, extension), do: {:error, {:unsupported, extension}}

  defp validate_reader({extension, {reader, opts}}) when is_binary(extension) and is_list(opts),
    do: validate_reader_module(extension, reader)

  defp validate_reader({extension, reader}) when is_binary(extension) and is_atom(reader),
    do: validate_reader_module(extension, reader)

  defp validate_reader({extension, reader}) do
    raise ArgumentError,
          "reader for #{inspect(extension)} must be a module or {module, opts}, got: #{inspect(reader)}"
  end

  defp validate_reader_module(extension, reader) do
    if not (is_atom(reader) and Code.ensure_loaded?(reader) and
              function_exported?(reader, :classify, 3)) do
      raise ArgumentError,
            "reader #{inspect(reader)} for #{inspect(extension)} must use Refract.Reader"
    end
  end
end
