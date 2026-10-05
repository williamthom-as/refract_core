defmodule Refract.Parse.Date do
  @moduledoc false

  alias Refract.Parse.Date.Pattern

  @type format :: :iso | :ymd | :dmy | :mdy | String.t()

  @type opt :: {:formats, [format()]}

  @spec parse(term(), [opt()]) :: {:ok, Date.t()} | {:error, {:not_a_date, term()}}

  def parse(value, opts) do
    opts = Keyword.validate!(opts, formats: [:iso, :ymd])
    formats = Keyword.fetch!(opts, :formats)

    parse_date(value, Enum.map(formats, &compile_format/1))
  end

  # patterns compile once here, so a bad one raises before any value is read
  defp compile_format(format) when format in [:iso, :ymd, :dmy, :mdy], do: format
  defp compile_format(pattern) when is_binary(pattern), do: {:pattern, Pattern.compile!(pattern)}

  defp compile_format(format) do
    raise ArgumentError, "unknown date format: #{inspect(format)}"
  end

  defp parse_date(%Date{} = date, _formats), do: {:ok, date}
  defp parse_date(%NaiveDateTime{} = naive, _formats), do: {:ok, NaiveDateTime.to_date(naive)}
  defp parse_date(%DateTime{} = date_time, _formats), do: {:ok, DateTime.to_date(date_time)}

  defp parse_date(value, formats) when is_binary(value) do
    trimmed = String.trim(value)

    Enum.find_value(formats, {:error, {:not_a_date, value}}, &date_in_format(&1, trimmed))
  end

  defp parse_date(value, _formats), do: {:error, {:not_a_date, value}}

  defp date_in_format(:iso, string) do
    case Date.from_iso8601(string) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> iso_date_time(string)
    end
  end

  defp date_in_format({:pattern, tokens}, string), do: Pattern.match(tokens, string)

  defp date_in_format(format, string) do
    case String.split(string, ["/", "-", "."]) do
      [first, second, third] -> numeric_date(format, first, second, third)
      _parts -> nil
    end
  end

  defp iso_date_time(string) do
    case NaiveDateTime.from_iso8601(string) do
      {:ok, naive} -> {:ok, NaiveDateTime.to_date(naive)}
      {:error, _reason} -> nil
    end
  end

  defp numeric_date(:ymd, year, month, day), do: build_date(year, month, day)
  defp numeric_date(:dmy, day, month, year), do: build_date(year, month, day)
  defp numeric_date(:mdy, month, day, year), do: build_date(year, month, day)

  defp build_date(year, month, day) do
    with true <- byte_size(year) == 4 and byte_size(month) <= 2 and byte_size(day) <= 2,
         {:ok, year} <- parse_integer(year),
         {:ok, month} <- parse_integer(month),
         {:ok, day} <- parse_integer(day),
         {:ok, date} <- Date.new(year, month, day) do
      {:ok, date}
    else
      _invalid -> nil
    end
  end

  defp parse_integer(string) do
    case Integer.parse(string) do
      {integer, ""} -> {:ok, integer}
      _ -> :error
    end
  end
end
