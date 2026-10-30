defmodule Refract.Parse.Date.Pattern do
  @moduledoc false

  @months %{
    "jan" => 1,
    "feb" => 2,
    "mar" => 3,
    "apr" => 4,
    "may" => 5,
    "jun" => 6,
    "jul" => 7,
    "aug" => 8,
    "sep" => 9,
    "oct" => 10,
    "nov" => 11,
    "dec" => 12
  }

  @type field :: :day | :month | :year

  @type token ::
          {:digits, field(), min :: pos_integer(), max :: pos_integer()}
          | {:century, 1900 | 2000}
          | :month_name
          | {:literal, String.t()}

  @spec compile!(String.t()) :: [token()]

  def compile!(pattern) do
    tokens =
      pattern
      |> String.split(~r/(?:19|20)yy/, include_captures: true, trim: true)
      |> Enum.flat_map(&runs/1)
      |> Enum.flat_map(&(&1 |> token(pattern) |> List.wrap()))

    validate_fields(tokens, pattern)

    tokens
  end

  @spec match([token()], String.t()) :: {:ok, Date.t()} | nil

  def match(tokens, string) do
    with {:ok, %{day: day, month: month, year: year} = fields} <- walk(tokens, string, %{}),
         {:ok, date} <- Date.new(Map.get(fields, :century, 0) + year, month, day) do
      {:ok, date}
    else
      _invalid -> nil
    end
  end

  defp runs(run) when run in ["19yy", "20yy"], do: [run]

  defp runs(run),
    do: run |> String.graphemes() |> Enum.chunk_by(& &1) |> Enum.map(&Enum.join/1)

  defp token("d", _pattern), do: {:digits, :day, 1, 2}
  defp token("dd", _pattern), do: {:digits, :day, 2, 2}
  defp token("M", _pattern), do: {:digits, :month, 1, 2}
  defp token("MM", _pattern), do: {:digits, :month, 2, 2}
  defp token("MMM", _pattern), do: :month_name
  defp token("yyyy", _pattern), do: {:digits, :year, 4, 4}
  defp token("20yy", _pattern), do: [{:century, 2000}, {:digits, :year, 2, 2}]
  defp token("19yy", _pattern), do: [{:century, 1900}, {:digits, :year, 2, 2}]

  defp token("yy", pattern) do
    raise ArgumentError,
          "date pattern \"yy\" needs a century, write 20yy or 19yy, got: #{inspect(pattern)}"
  end

  defp token(<<char, _rest::binary>> = run, pattern) when char in ?a..?z or char in ?A..?Z do
    raise ArgumentError, "unknown date pattern letters #{inspect(run)} in #{inspect(pattern)}"
  end

  defp token(run, _pattern), do: {:literal, run}

  defp validate_fields(tokens, pattern) do
    fields = for {:digits, field, _min, _max} <- tokens, do: field
    fields = if :month_name in tokens, do: [:month | fields], else: fields

    if Enum.sort(fields) != [:day, :month, :year] do
      raise ArgumentError,
            "date pattern needs day, month and year once each, got: #{inspect(pattern)}"
    end
  end

  defp walk([], "", fields), do: {:ok, fields}
  defp walk([], _rest, _fields), do: nil

  defp walk([{:century, century} | tokens], string, fields),
    do: walk(tokens, string, Map.put(fields, :century, century))

  defp walk([{:literal, literal} | tokens], string, fields) do
    size = byte_size(literal)

    case string do
      <<^literal::binary-size(^size), rest::binary>> -> walk(tokens, rest, fields)
      _mismatch -> nil
    end
  end

  defp walk([:month_name | tokens], <<name::binary-size(3), rest::binary>>, fields) do
    case Map.fetch(@months, String.downcase(name)) do
      {:ok, month} -> walk(tokens, rest, Map.put(fields, :month, month))
      :error -> nil
    end
  end

  defp walk([:month_name | _tokens], _short, _fields), do: nil

  defp walk([{:digits, field, min, max} | tokens], string, fields) do
    {digits, rest} = leading_digits(string, max, "")

    if byte_size(digits) >= min do
      walk(tokens, rest, Map.put(fields, field, String.to_integer(digits)))
    end
  end

  defp leading_digits(<<char, rest::binary>>, max, digits)
       when char in ?0..?9 and byte_size(digits) < max do
    leading_digits(rest, max, digits <> <<char>>)
  end

  defp leading_digits(rest, _max, digits), do: {digits, rest}
end
