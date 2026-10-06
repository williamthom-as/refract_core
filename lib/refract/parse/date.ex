defmodule Refract.Parse.Date do
  @moduledoc false

  alias Refract.Parse.Date.Pattern

  @type format :: :iso | :ymd | :dmy | :mdy | String.t()

  @type opt :: {:formats, [format()]}

  @time ~r/^(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?$/

  @spec parse(term(), [opt()]) :: {:ok, Date.t()} | {:error, {:not_a_date, term()}}

  def parse(value, opts) do
    case scan(value, formats(opts), :optional) do
      {:ok, date, _time} -> {:ok, date}
      nil -> {:error, {:not_a_date, value}}
    end
  end

  @spec parse_datetime(term(), [opt()]) ::
          {:ok, NaiveDateTime.t()} | {:error, {:not_a_datetime, term()}}

  def parse_datetime(value, opts) do
    case scan(value, formats(opts), :required) do
      {:ok, date, time} -> NaiveDateTime.new(date, time)
      nil -> {:error, {:not_a_datetime, value}}
    end
  end

  defp formats(opts) do
    opts = Keyword.validate!(opts, formats: [:iso, :ymd])

    opts
    |> Keyword.fetch!(:formats)
    |> Enum.map(&compile_format/1)
  end

  # patterns compile once here, so a bad one raises before any value is read
  defp compile_format(format) when format in [:iso, :ymd, :dmy, :mdy], do: format
  defp compile_format(pattern) when is_binary(pattern), do: {:pattern, Pattern.compile!(pattern)}

  defp compile_format(format) do
    raise ArgumentError, "unknown date format: #{inspect(format)}"
  end

  defp scan(%Date{} = date, _formats, :optional), do: {:ok, date, nil}
  defp scan(%Date{}, _formats, :required), do: nil

  defp scan(%NaiveDateTime{} = naive, _formats, _rule),
    do: {:ok, NaiveDateTime.to_date(naive), NaiveDateTime.to_time(naive)}

  defp scan(%DateTime{} = date_time, formats, rule),
    do: date_time |> DateTime.to_naive() |> scan(formats, rule)

  defp scan(value, formats, rule) when is_binary(value) do
    value
    |> String.trim()
    |> splits()
    |> Enum.find_value(fn {date_part, time_part} ->
      with {:ok, date} <- find_date(date_part, formats),
           {:ok, time} <- scan_time(time_part, rule) do
        {:ok, date, time}
      end
    end)
  end

  defp scan(_value, _formats, _rule), do: nil

  defp splits(string) do
    [{string, nil}] ++ split_last(string, " ") ++ split_last(string, "T")
  end

  defp split_last(string, separator) do
    case string |> String.reverse() |> String.split(separator, parts: 2) do
      [_only] -> []
      [time, date] -> [{String.reverse(date), String.reverse(time)}]
    end
  end

  defp find_date(string, formats) do
    Enum.find_value(formats, &date_in_format(&1, string))
  end

  defp scan_time(nil, :optional), do: {:ok, nil}
  defp scan_time(nil, :required), do: nil

  defp scan_time(string, _rule) do
    with [_all, hour, minute | rest] <- Regex.run(@time, string),
         {:ok, time} <- Time.new(to_int(hour), to_int(minute), to_int(List.first(rest, "0"))) do
      {:ok, time}
    else
      _invalid -> nil
    end
  end

  defp to_int(""), do: 0
  defp to_int(digits), do: String.to_integer(digits)

  defp date_in_format(:iso, string) do
    case Date.from_iso8601(string) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> nil
    end
  end

  defp date_in_format({:pattern, tokens}, string), do: Pattern.match(tokens, string)

  defp date_in_format(format, string) do
    case String.split(string, ["/", "-", "."]) do
      [first, second, third] -> numeric_date(format, first, second, third)
      _parts -> nil
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
