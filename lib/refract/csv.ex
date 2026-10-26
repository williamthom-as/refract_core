defmodule Refract.CSV do
  @moduledoc """
  csv reader and writer impls, providing `stream`, `locate`, `load`, `write`, `write_chunks`
  detects the separator (comma, semicolon, tab, pipe) unless given via `separator:`
  will strip utf8 bom by default, and fail fast on a missing file.
  `encoding: :auto` (default) keeps each line that is valid utf8 and reads any other as
  windows-1252; `:utf8`, `:latin1` and `:windows_1252` force one. a utf16 file is an error.
  `bom: true` writes a utf8 bom first, so excel reads the file as utf8.
  lines end at `\r\n` or `\n`, mixed freely. a path or string whose lines end only in `\r` (old
  mac exports) is an error. a `{:stream, chunks}` source is never read ahead, so neither check
  applies to it.

      {:ok, rows} = Refract.CSV.stream("bills.csv", skip: 1)
      :ok = Refract.CSV.write(rows, "out/bills.csv", header: ["date", "cost"])
  """

  use Refract.Reader
  use Refract.Writer

  alias Refract.CSV.Encoding
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
    opts = Keyword.validate!(opts, separator: :detect, encoding: :auto)
    encoding = Keyword.fetch!(opts, :encoding)

    Encoding.validate!(encoding)

    with {:ok, format} <- Facts.format(source, Keyword.fetch!(opts, :separator)),
         :ok <- supported(format, encoding),
         {:ok, parser} <- Parsers.for_separator(format.separator),
         {:ok, content} <- Source.open(source, opts) do
      {:ok,
       content
       |> parser.to_line_stream()
       |> Source.strip_bom()
       |> Encoding.decode(encoding)
       |> parser.parse_stream(skip_headers: false)
       |> ParseError.translate(NimbleCSV.ParseError)}
    end
  end

  @spec encode(rows :: Enumerable.t(), opts :: keyword()) :: Enumerable.t()

  @impl true
  def encode(rows, opts) do
    opts = Keyword.validate!(opts, header: nil, separator: ",", bom: false)

    {:ok, parser} = Parsers.for_separator(Keyword.fetch!(opts, :separator))

    rows
    |> Writer.cells(Keyword.fetch!(opts, :header))
    |> parser.dump_to_stream()
    |> with_bom(Keyword.fetch!(opts, :bom))
  end

  @spec facts(source :: Refract.source(), keyword()) :: {:ok, map()} | {:error, term()}

  @impl true
  def facts(source, opts \\ []), do: Facts.run(source, opts)

  defp supported(%{utf16: true}, :auto), do: {:error, {:unsupported_encoding, :utf16}}
  defp supported(%{line_endings: :cr}, _encoding), do: {:error, {:unsupported_line_endings, :cr}}
  defp supported(_format, _encoding), do: :ok

  defp with_bom(lines, true), do: Stream.concat([<<0xEF, 0xBB, 0xBF>>], lines)
  defp with_bom(lines, false), do: lines
end
