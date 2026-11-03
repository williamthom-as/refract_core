defmodule Refract.CSV do
  @moduledoc """
  CSV reader and writer impls, providing `stream`, `locate`, `load`, `write`, `write_chunks`
  detects the separator (comma, semicolon, tab, pipe) unless given via `separator:`
  will strip utf8 bom by default, and fail fast on a missing file.

  `encoding: :auto` (default) keeps each line that is valid utf8 and reads any other as
  windows-1252; `:utf8`, `:latin1` and `:windows_1252` force one. a utf16 file is an error.
  `bom: true` writes a utf8 bom first, so excel reads the file as utf8.

  `escape_formulas: true` (default) writing mode escapes formulas by default following owasp
  CSV injection best practise rules
  - a text cell starting with `=`, `+`,`-`, `@`, carriage return, line feed or their full width
  form gets escaped via a tab first, inside a quoted field.
  for example, the tab stays in the data (`-12.50` is written `"\t-12.50"`). pass
  `escape_formulas: false` when a program (not a person/human read) reads the file.

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

  @spec open_options() :: keyword()

  @impl Refract.Reader
  def open_options, do: [separator: :detect, encoding: :auto]

  @spec encode_options() :: keyword()

  @impl Refract.Writer
  def encode_options, do: [header: nil, separator: ",", bom: false, escape_formulas: true]

  @spec open(source :: Refract.source(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}

  @impl true
  def open(source, opts) do
    opts = Keyword.validate!(opts, open_options())
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
    opts = Keyword.validate!(opts, encode_options())
    escape_formulas = Keyword.fetch!(opts, :escape_formulas)

    validate_escape_formulas(escape_formulas)

    parser = opts |> Keyword.fetch!(:separator) |> Parsers.for_separator() |> dump_parser!()

    rows
    |> Writer.cells(Keyword.fetch!(opts, :header))
    |> escape_formulas(escape_formulas)
    |> parser.dump_to_stream()
    |> with_bom(Keyword.fetch!(opts, :bom))
  end

  @spec facts(source :: Refract.source(), keyword()) :: {:ok, map()} | {:error, term()}

  @impl true
  def facts(source, opts \\ []), do: Facts.run(source, Keyword.validate!(opts, open_options()))

  defp supported(%{utf16: true}, :auto), do: {:error, {:unsupported_encoding, :utf16}}
  defp supported(%{line_endings: :cr}, _encoding), do: {:error, {:unsupported_line_endings, :cr}}
  defp supported(_format, _encoding), do: :ok

  defp validate_escape_formulas(escape_formulas) when is_boolean(escape_formulas), do: :ok

  defp validate_escape_formulas(escape_formulas) do
    raise ArgumentError, "escape_formulas must be true or false, got: #{inspect(escape_formulas)}"
  end

  defp escape_formulas(lines, false), do: lines

  defp escape_formulas(lines, true),
    do: Stream.map(lines, &Enum.map(&1, fn cell -> escaped(cell) end))

  defp escaped(cell) when is_binary(cell), do: cell |> formula?() |> escaped(cell)
  defp escaped(cell), do: cell

  defp escaped(true, cell), do: "\t" <> cell
  defp escaped(false, cell), do: cell

  defp formula?(cell),
    do:
      String.starts_with?(cell, [
        "=",
        "+",
        "-",
        "@",
        "\r",
        "\n",
        "\uFF1D",
        "\uFF0B",
        "\uFF0D",
        "\uFF20"
      ])

  defp dump_parser!({:ok, parser}), do: parser

  defp dump_parser!({:error, {:unsupported_separator, separator}}) do
    raise ArgumentError,
          "separator must be one of \",\", \";\", \"\\t\", \"|\", got: #{inspect(separator)}"
  end

  defp with_bom(lines, true), do: Stream.concat([<<0xEF, 0xBB, 0xBF>>], lines)
  defp with_bom(lines, false), do: lines
end
