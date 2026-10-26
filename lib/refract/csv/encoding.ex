defmodule Refract.CSV.Encoding do
  @moduledoc false

  @type t :: :auto | :utf8 | :latin1 | :windows_1252

  @windows_1252 %{
    0x80 => 0x20AC,
    0x82 => 0x201A,
    0x83 => 0x0192,
    0x84 => 0x201E,
    0x85 => 0x2026,
    0x86 => 0x2020,
    0x87 => 0x2021,
    0x88 => 0x02C6,
    0x89 => 0x2030,
    0x8A => 0x0160,
    0x8B => 0x2039,
    0x8C => 0x0152,
    0x8E => 0x017D,
    0x91 => 0x2018,
    0x92 => 0x2019,
    0x93 => 0x201C,
    0x94 => 0x201D,
    0x95 => 0x2022,
    0x96 => 0x2013,
    0x97 => 0x2014,
    0x98 => 0x02DC,
    0x99 => 0x2122,
    0x9A => 0x0161,
    0x9B => 0x203A,
    0x9C => 0x0153,
    0x9E => 0x017E,
    0x9F => 0x0178
  }

  @c1_bytes for byte <- 0x80..0x9F, do: <<byte>>

  @spec validate!(term()) :: :ok

  def validate!(encoding) when encoding in [:auto, :utf8, :latin1, :windows_1252], do: :ok

  def validate!(encoding) do
    raise ArgumentError,
          "encoding must be :auto, :utf8, :latin1 or :windows_1252, got: #{inspect(encoding)}"
  end

  @spec utf16?(binary()) :: boolean()

  def utf16?(<<0xFF, 0xFE, _rest::binary>>), do: true
  def utf16?(<<0xFE, 0xFF, _rest::binary>>), do: true
  def utf16?(_bytes), do: false

  @spec decode(Enumerable.t(), t()) :: Enumerable.t()

  def decode(lines, :utf8), do: lines

  def decode(lines, encoding) do
    c1 = :binary.compile_pattern(@c1_bytes)

    Stream.map(lines, &line(&1, encoding, c1))
  end

  defp line(line, :auto, c1), do: line |> String.valid?() |> auto(line, c1)
  defp line(line, :latin1, _c1), do: :unicode.characters_to_binary(line, :latin1)
  defp line(line, :windows_1252, c1), do: windows_1252(line, c1)

  defp auto(true, line, _c1), do: line
  defp auto(false, line, c1), do: windows_1252(line, c1)

  defp windows_1252(line, c1), do: line |> :binary.match(c1) |> windows_1252_line(line)

  defp windows_1252_line(:nomatch, line), do: :unicode.characters_to_binary(line, :latin1)

  defp windows_1252_line(_c1_byte, line),
    do: for(<<byte <- line>>, into: "", do: <<Map.get(@windows_1252, byte, byte)::utf8>>)
end
