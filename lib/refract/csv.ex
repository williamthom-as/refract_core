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

  alias Refract.CSV.Parsers
  alias Refract.CSV.Source

  @impl Refract.Writer
  def extension, do: "csv"

  @spec open(source :: Refract.source(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}

  @impl true
  def open(source, opts) do
    with {:ok, parser} <- Parsers.for_separator(Keyword.get(opts, :separator, ",")),
         {:ok, content} <- Source.open(source, opts) do
      {:ok,
       content
       |> parser.to_line_stream()
       |> Source.strip_bom()
       |> parser.parse_stream(skip_headers: false)}
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
