defmodule Refract.CSV do
  @moduledoc """
  csv reader and writer impls, providing `stream`, `locate`, `load`, `write`, `write_chunks`
  supports different separators like comma, semicolon, tab, pipe via `separator:`
  will strip utf8 bom by default, and fail fast on a missing file.

      {:ok, rows} = Refract.CSV.stream("bills.csv", skip: 1)
      :ok = Refract.CSV.write(rows, "out/bills.csv", header: ["date", "cost"])
  """

  use Refract.Reader
  use Refract.Writer

  alias Refract.CSV.Facts
  alias Refract.CSV.Parsers
  alias Refract.CSV.Source
  alias Refract.Reader.ParseErrors

  @impl Refract.Writer
  def extension, do: "csv"

  @spec open(source :: Refract.source(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}

  @impl true
  def open(source, opts) do
    with {:ok, separator} <- separator(source, Keyword.get(opts, :separator, ",")),
         {:ok, parser} <- Parsers.for_separator(separator),
         {:ok, content} <- Source.open(source, opts) do
      {:ok,
       content
       |> parser.to_line_stream()
       |> Source.strip_bom()
       |> parser.parse_stream(skip_headers: false)
       |> ParseErrors.translate(NimbleCSV.ParseError)}
    end
  end

  @spec encode(rows :: Enumerable.t(), opts :: keyword()) :: Enumerable.t()

  @impl true
  def encode(rows, opts) do
    {:ok, parser} = Parsers.for_separator(Keyword.get(opts, :separator, ","))

    rows
    |> to_cells(Keyword.get(opts, :header))
    |> parser.dump_to_stream()
  end

  @spec facts(source :: Refract.source(), keyword()) :: {:ok, map()} | {:error, term()}

  @impl true
  def facts(source, opts \\ []), do: Facts.run(source, opts)

  @spec classify(Refract.source(), [Refract.Shape.t() | module()], keyword()) ::
          {:ok, Refract.Classify.Result.t()} | {:error, term()}

  def classify(source, shapes, opts \\ []),
    do:
      Refract.Reader.classify(
        __MODULE__,
        source,
        shapes,
        Keyword.put_new(opts, :separator, :detect)
      )

  defp separator({:stream, _chunks}, :detect), do: {:ok, ","}
  defp separator(source, :detect), do: Facts.separator(source)
  defp separator(_source, separator), do: {:ok, separator}

  defp to_cells(rows, nil) do
    Stream.transform(rows, nil, fn
      row, nil ->
        header = row |> Map.keys() |> Enum.sort()

        {[header, fetch_ordered_values(row, header)], header}

      row, header ->
        {[fetch_ordered_values(row, header)], header}
    end)
  end

  defp to_cells(rows, header) do
    Stream.concat(
      [header],
      Stream.map(rows, &fetch_ordered_values(&1, header))
    )
  end

  defp fetch_ordered_values(row, headers) do
    Enum.map(headers, fn header -> Map.fetch!(row, header) end)
  end
end
