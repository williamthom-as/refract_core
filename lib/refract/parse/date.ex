defmodule Refract.Parse.Date do
  @moduledoc false

  alias Refract.Parse.Date.Pattern

  @type format :: :iso | :ymd | :dmy | :mdy | String.t()

  @type offset :: :reject | :utc

  @type opt :: {:formats, [format()]}

  @type datetime_opt :: opt() | {:offset, offset()}

  @type datetime_error :: {:not_a_datetime, term()} | {:has_offset, term()}

  @time ~r/^(?<hour>\d{1,2}):(?<minute>\d{2})(?::(?<second>\d{2})(?:\.(?<fraction>\d+))?)?(?<offset>Z|[+-]\d{2}:?\d{2})?$/

  @meridiem ~r/(?<=\d)\s*([ap])\.?m\.?$/i

  @spec parse(term(), [opt()]) :: {:ok, Date.t()} | {:error, {:not_a_date, term()}}

  def parse(value, opts) do
    opts = Keyword.validate!(opts, formats: [:iso, :ymd])

    formats = opts |> Keyword.fetch!(:formats) |> compile_formats()

    case iso(value, formats, :optional) || scan(value, formats, :optional) do
      {:ok, date, _time, _offset} -> {:ok, date}
      nil -> {:error, {:not_a_date, value}}
    end
  end

  @spec parse_datetime(term(), [datetime_opt()]) ::
          {:ok, NaiveDateTime.t()} | {:error, datetime_error()}

  def parse_datetime(value, opts) do
    opts = Keyword.validate!(opts, formats: [:iso, :ymd], offset: :reject)

    formats = opts |> Keyword.fetch!(:formats) |> compile_formats()
    offset = Keyword.fetch!(opts, :offset)

    validate_offset(offset)

    case iso(value, formats, :required) || scan(value, formats, :required) do
      {:ok, date, time, seconds} ->
        date
        |> NaiveDateTime.new!(time)
        |> apply_offset(seconds, offset, value)

      nil ->
        {:error, {:not_a_datetime, value}}
    end
  end

  defp validate_offset(offset) when offset in [:reject, :utc], do: :ok

  defp validate_offset(offset) do
    raise ArgumentError, "offset must be :reject or :utc, got: #{inspect(offset)}"
  end

  defp apply_offset(naive, 0, _offset, _value), do: {:ok, naive}
  defp apply_offset(naive, seconds, :utc, _value), do: {:ok, NaiveDateTime.add(naive, -seconds)}
  defp apply_offset(_naive, _seconds, :reject, value), do: {:error, {:has_offset, value}}

  defp compile_formats(formats), do: Enum.map(formats, &compile_format/1)

  # patterns compile once here, so a bad one raises before any value is read
  defp compile_format(format) when format in [:iso, :ymd, :dmy, :mdy], do: format
  defp compile_format(pattern) when is_binary(pattern), do: {:pattern, Pattern.compile!(pattern)}

  defp compile_format(format) do
    raise ArgumentError, "unknown date format: #{inspect(format)}"
  end

  defp iso(value, [:iso | _formats], rule) when is_binary(value),
    do: value |> String.trim() |> iso_shape(rule)

  defp iso(_value, _formats, _rule), do: nil

  defp iso_shape(
         <<_::binary-size(4), ?-, _::binary-size(2), ?-, _::binary-size(2)>> = string,
         :optional
       ) do
    case Date.from_iso8601(string) do
      {:ok, date} -> {:ok, date, nil, 0}
      {:error, _reason} -> nil
    end
  end

  defp iso_shape(<<date_time::binary-size(19), ?Z>>, rule), do: iso_shape(date_time, rule)

  defp iso_shape(<<_::binary-size(10), separator, _::binary-size(8)>> = string, _rule)
       when separator in [?T, ?\s] do
    case NaiveDateTime.from_iso8601(string) do
      {:ok, naive} -> {:ok, NaiveDateTime.to_date(naive), NaiveDateTime.to_time(naive), 0}
      {:error, _reason} -> nil
    end
  end

  defp iso_shape(_string, _rule), do: nil

  defp scan(%Date{} = date, _formats, :optional), do: {:ok, date, nil, 0}
  defp scan(%Date{}, _formats, :required), do: nil

  defp scan(%NaiveDateTime{} = naive, _formats, _rule),
    do: {:ok, NaiveDateTime.to_date(naive), NaiveDateTime.to_time(naive), 0}

  defp scan(%DateTime{} = date_time, _formats, _rule) do
    naive = DateTime.to_naive(date_time)

    {:ok, NaiveDateTime.to_date(naive), NaiveDateTime.to_time(naive),
     date_time.utc_offset + date_time.std_offset}
  end

  defp scan(value, formats, rule) when is_binary(value) do
    {string, meridiem} = value |> String.trim() |> split_meridiem()

    string
    |> splits()
    |> Enum.find_value(fn {date_part, time_part} ->
      with {:ok, date} <- find_date(date_part, formats),
           {:ok, time, offset} <- scan_time(time_part, meridiem, rule) do
        {:ok, date, time, offset}
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

  defp split_meridiem(string) do
    case Regex.run(@meridiem, string) do
      [_all, letter] -> {Regex.replace(@meridiem, string, ""), meridiem(String.downcase(letter))}
      nil -> {string, nil}
    end
  end

  defp meridiem("a"), do: :am
  defp meridiem("p"), do: :pm

  defp scan_time(nil, nil, :optional), do: {:ok, nil, 0}
  defp scan_time(nil, _meridiem, _rule), do: nil

  defp scan_time(string, meridiem, _rule) do
    with %{"hour" => hour, "minute" => minute, "second" => second} = parts <-
           Regex.named_captures(@time, string),
         {:ok, hour} <- clock_hour(to_int(hour), meridiem),
         {:ok, time} <-
           Time.new(hour, to_int(minute), to_int(second), fraction(parts["fraction"])) do
      {:ok, time, offset_seconds(parts["offset"])}
    else
      _invalid -> nil
    end
  end

  defp clock_hour(hour, nil), do: {:ok, hour}
  defp clock_hour(hour, _meridiem) when hour < 1 or hour > 12, do: :error
  defp clock_hour(12, :am), do: {:ok, 0}
  defp clock_hour(12, :pm), do: {:ok, 12}
  defp clock_hour(hour, :am), do: {:ok, hour}
  defp clock_hour(hour, :pm), do: {:ok, hour + 12}

  defp fraction(""), do: {0, 0}

  defp fraction(digits) do
    kept = String.slice(digits, 0, 6)

    {kept |> String.pad_trailing(6, "0") |> String.to_integer(), String.length(kept)}
  end

  defp offset_seconds(""), do: 0
  defp offset_seconds("Z"), do: 0

  defp offset_seconds(<<sign, hours::binary-size(2), minutes::binary>>) do
    seconds = (to_int(hours) * 60 + to_int(String.trim_leading(minutes, ":"))) * 60

    signed(sign, seconds)
  end

  defp signed(?-, seconds), do: -seconds
  defp signed(?+, seconds), do: seconds

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
