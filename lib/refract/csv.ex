defmodule Refract.CSV do
  @moduledoc """
  csv reader and writer impls, providing `stream`, `locate`, `load`, `write`, `write_chunks`
  detects the separator (comma, semicolon, tab, pipe) unless given via `separator:`
  will strip utf8 bom by default, and fail fast on a missing file.

      {:ok, rows} = Refract.CSV.stream("bills.csv", skip: 1)
      :ok = Refract.CSV.write(rows, "out/bills.csv", header: ["date", "cost"])
  """

  use Refract.Reader
  use Refract.Writer

  alias Refract.CSV.Facts
  alias Refract.CSV.Parsers
  alias Refract.CSV.Source
  alias Refract.Errors.ParseError
  alias Refract.Writer

  @impl Refract.Writer
  def extension, do: "csv"

  @impl Refract.Reader
  def extensions, do: ["csv", "tsv"]

  @spec open(source :: Refract.source(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}

  @impl true
  def open(source, opts) do
    opts = Keyword.validate!(opts, separator: :detect)

    with {:ok, separator} <- separator(source, Keyword.fetch!(opts, :separator)),
         {:ok, parser} <- Parsers.for_separator(separator),
         {:ok, content} <- Source.open(source, opts) do
      {:ok,
       content
       |> parser.to_line_stream()
       |> Source.strip_bom()
       |> parser.parse_stream(skip_headers: false)
       |> ParseError.translate(NimbleCSV.ParseError)}
    end
  end

  @spec encode(rows :: Enumerable.t(), opts :: keyword()) :: Enumerable.t()

  @impl true
  def encode(rows, opts) do
    {:ok, parser} = Parsers.for_separator(Keyword.get(opts, :separator, ","))

    rows
    |> Writer.cells(Keyword.get(opts, :header))
    |> parser.dump_to_stream()
  end

  @spec facts(source :: Refract.source(), keyword()) :: {:ok, map()} | {:error, term()}

  @impl true
  def facts(source, opts \\ []), do: Facts.run(source, opts)

  defp separator({:stream, _chunks}, :detect), do: {:ok, ","}
  defp separator(source, :detect), do: Facts.separator(source)
  defp separator(_source, separator), do: {:ok, separator}
end
