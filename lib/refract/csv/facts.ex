defmodule Refract.CSV.Facts do
  @moduledoc false

  alias Refract.CSV.Encoding

  @head_bytes 65_536

  @separators [",", ";", "\t", "|"]

  @separator_bytes [?,, ?;, ?\t, ?|]

  @type separator :: String.t()

  @type separator_source :: :detected | :given | :default

  @type line_ending :: :lf | :crlf | :cr

  @type line_endings :: line_ending() | :mixed | :none

  @type encoding :: Encoding.t() | :mixed | :utf16

  @type encoding_source :: :detected | :given

  @type format :: %{separator: separator(), line_endings: line_endings(), utf16: boolean()}

  @type t :: %{
          encoding: encoding(),
          encoding_source: encoding_source(),
          bom: boolean(),
          delimiter: separator(),
          delimiter_source: separator_source(),
          line_endings: line_endings(),
          line_ending_counts: %{optional(line_ending()) => pos_integer()},
          trailing_newline: boolean() | :unknown
        }

  @spec run(Refract.source(), keyword()) :: {:ok, t()} | {:error, term()}

  def run(source, opts) do
    separator = Keyword.get(opts, :separator, :detect)
    encoding = Keyword.get(opts, :encoding, :auto)

    Encoding.validate!(encoding)

    with {:ok, head} <- head(source),
         {:ok, trailing_newline} <- trailing_newline(source) do
      {bom, body} = bom(head)
      {counts, lines} = scan(body, false, %{}, %{}, [])
      {delimiter, delimiter_source} = delimiter(separator, lines)
      {encoding, encoding_source} = encoding(encoding, head, body)

      {:ok,
       %{
         encoding: encoding,
         encoding_source: encoding_source,
         bom: bom,
         delimiter: delimiter,
         delimiter_source: delimiter_source,
         line_endings: line_endings(counts),
         line_ending_counts: counts,
         trailing_newline: trailing_newline
       }}
    end
  end

  @spec format(Refract.source(), separator() | :detect) :: {:ok, format()} | {:error, term()}

  def format({:stream, _chunks}, separator),
    do: {:ok, %{separator: stream_separator(separator), line_endings: :none, utf16: false}}

  def format(source, separator) do
    with {:ok, head} <- head(source) do
      {_bom, body} = bom(head)
      {counts, lines} = scan(body, false, %{}, %{}, [])
      {separator, _source} = delimiter(separator, lines)

      {:ok,
       %{separator: separator, line_endings: line_endings(counts), utf16: Encoding.utf16?(head)}}
    end
  end

  defp stream_separator(:detect), do: ","
  defp stream_separator(separator), do: separator

  defp head({:string, string}),
    do: {:ok, binary_part(string, 0, min(byte_size(string), @head_bytes))}

  defp head({:stream, chunks}) do
    {:ok,
     Enum.reduce_while(chunks, "", fn chunk, acc ->
       if byte_size(acc) >= @head_bytes, do: {:halt, acc}, else: {:cont, acc <> chunk}
     end)}
  end

  defp head(path) when is_binary(path) do
    with {:ok, file} <- File.open(path, [:read, :binary]) do
      bytes = IO.binread(file, @head_bytes)

      File.close(file)

      {:ok, read_bytes(bytes)}
    end
  end

  defp head(source), do: {:error, {:unsupported_source, source}}

  defp read_bytes(:eof), do: ""
  defp read_bytes(bytes), do: bytes

  defp trailing_newline({:string, ""}), do: {:ok, false}
  defp trailing_newline({:string, string}), do: {:ok, line_ending?(:binary.last(string))}
  defp trailing_newline({:stream, _chunks}), do: {:ok, :unknown}

  defp trailing_newline(path) when is_binary(path) do
    with {:ok, %File.Stat{size: size}} <- File.stat(path) do
      last_byte(path, size)
    end
  end

  defp last_byte(_path, 0), do: {:ok, false}

  defp last_byte(path, size) do
    with {:ok, file} <- File.open(path, [:read, :binary]) do
      {:ok, <<byte>>} = :file.pread(file, size - 1, 1)

      File.close(file)

      {:ok, line_ending?(byte)}
    end
  end

  defp line_ending?(byte), do: byte in [?\n, ?\r]

  defp encoding(:auto, head, body),
    do: {detect_encoding(Encoding.utf16?(head), head, body), :detected}

  defp encoding(given, _head, _body), do: {given, :given}

  defp detect_encoding(true, _head, _body), do: :utf16

  defp detect_encoding(false, head, body) do
    lines = body |> String.split(["\r\n", "\n", "\r"]) |> whole_lines(byte_size(head))

    lines
    |> Enum.reject(&String.valid?/1)
    |> detected_encoding(Enum.any?(lines, &wide?/1))
  end

  defp whole_lines(lines, size) when size >= @head_bytes, do: Enum.drop(lines, -1)
  defp whole_lines(lines, _size), do: lines

  defp wide?(line), do: String.valid?(line) and byte_size(line) != String.length(line)

  defp detected_encoding([], _wide), do: :utf8
  defp detected_encoding(_invalid, true), do: :mixed
  defp detected_encoding(_invalid, false), do: :windows_1252

  defp bom("\uFEFF" <> body), do: {true, body}
  defp bom(body), do: {false, body}

  defp scan(<<?", rest::binary>>, in_quote, counts, line, lines),
    do: scan(rest, not in_quote, counts, line, lines)

  defp scan(<<"\r\n", rest::binary>>, false, counts, line, lines),
    do: scan(rest, false, count(counts, :crlf), %{}, [line | lines])

  defp scan(<<"\n", rest::binary>>, false, counts, line, lines),
    do: scan(rest, false, count(counts, :lf), %{}, [line | lines])

  defp scan(<<"\r", rest::binary>>, false, counts, line, lines),
    do: scan(rest, false, count(counts, :cr), %{}, [line | lines])

  defp scan(<<byte, rest::binary>>, false, counts, line, lines) when byte in @separator_bytes,
    do: scan(rest, false, counts, count(line, <<byte>>), lines)

  defp scan(<<_byte, rest::binary>>, in_quote, counts, line, lines),
    do: scan(rest, in_quote, counts, line, lines)

  defp scan(<<>>, _in_quote, counts, line, lines), do: {counts, Enum.reverse([line | lines])}

  defp count(counts, key), do: Map.update(counts, key, 1, &(&1 + 1))

  defp line_endings(counts) when map_size(counts) == 0, do: :none
  defp line_endings(counts) when map_size(counts) == 1, do: counts |> Map.keys() |> hd()
  defp line_endings(_counts), do: :mixed

  defp delimiter(:detect, lines), do: detect(lines)
  defp delimiter(separator, _lines), do: {separator, :given}

  defp detect(lines) do
    @separators
    |> Enum.flat_map(&coverage(&1, lines))
    |> pick_separator()
  end

  defp coverage(separator, lines) do
    lines
    |> Enum.map(&Map.get(&1, separator, 0))
    |> Enum.filter(&(&1 > 0))
    |> separator_coverage(separator)
  end

  defp separator_coverage([], _separator), do: []

  defp separator_coverage(counts, separator) do
    {mode, _lines} =
      counts |> Enum.frequencies() |> Enum.max_by(fn {count, lines} -> {lines, count} end)

    [{separator, {Enum.count(counts, &(&1 == mode)), mode}}]
  end

  defp pick_separator([]), do: {",", :default}

  defp pick_separator(scored) do
    {separator, _coverage} = Enum.max_by(scored, fn {_separator, coverage} -> coverage end)

    {separator, :detected}
  end
end
