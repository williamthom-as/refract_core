defmodule Refract.Parse do
  @moduledoc """
  parses cells into typed values:
  - numbers are `Decimal` (`locale:` picks the separators, `currency: true` allows a currency
  sign or code and accounting parentheses)
  - dates try iso first, day or month first never guessed, custom patterns supported
  via `formats:`
  - datetimes take same `formats:` for the date component with a time trailing after

  note: each version comes with optional bang version that raises on failure.

      iex> Refract.Parse.number("1,234.56")
      {:ok, Decimal.new("1234.56")}

      iex> Refract.Parse.number("1.234,56", locale: :de)
      {:ok, Decimal.new("1234.56")}

      iex> Refract.Parse.number("($1,234.56)", currency: true)
      {:ok, Decimal.new("-1234.56")}

      iex> Refract.Parse.date("02-Oct-2026", formats: ["dd-MMM-yyyy", :iso])
      {:ok, ~D[2026-10-02]}

      iex> Refract.Parse.datetime("02/10/2026 9:30", formats: [:dmy])
      {:ok, ~N[2026-10-02 09:30:00]}

      iex> Refract.Parse.boolean("Yes")
      {:ok, true}

      iex> Refract.Parse.integer("12a")
      {:error, {:not_an_integer, "12a"}}
  """

  alias Refract.Parse.Date, as: DateParser

  import Refract.String.Utils, only: [normalise: 1]

  @type locale :: :en | :de

  @type number_opt :: {:locale, locale()} | {:currency, boolean()}

  @currency_symbols ["$", "£", "€", "¥"]

  # number

  @spec number(term(), [number_opt()]) :: {:ok, Decimal.t()} | {:error, {:not_a_number, term()}}

  def number(value, opts \\ []) do
    opts = Keyword.validate!(opts, locale: :en, currency: false)
    separator = separators(Keyword.fetch!(opts, :locale))

    validate_currency(Keyword.fetch!(opts, :currency))

    value
    |> strip_currency(Keyword.fetch!(opts, :currency))
    |> parse_number(separator)
    |> restore_value(value)
  end

  @spec number!(term(), [number_opt()]) :: Decimal.t()

  def number!(value, opts \\ []) do
    case number(value, opts) do
      {:ok, decimal} ->
        decimal

      {:error, reason} ->
        raise ArgumentError, "cannot parse #{inspect(value)} as a number: #{inspect(reason)}"
    end
  end

  defp validate_currency(currency) when is_boolean(currency), do: :ok

  defp validate_currency(currency),
    do: raise(ArgumentError, "currency must be true or false, got: #{inspect(currency)}")

  defp strip_currency(value, true) when is_binary(value) do
    {sign, amount} = value |> String.trim() |> accounting_sign()
    {lead, amount} = leading_sign(amount)

    sign <> lead <> (amount |> strip_leading_currency() |> strip_trailing_currency())
  end

  defp strip_currency(value, _currency), do: value

  defp strip_leading_currency(amount) do
    {code, rest} = String.split_at(amount, code_length(amount))

    cond do
      String.starts_with?(rest, @currency_symbols) ->
        rest |> String.slice(1..-1//1) |> String.trim()

      code != "" and String.starts_with?(rest, " ") ->
        String.trim(rest)

      true ->
        amount
    end
  end

  defp strip_trailing_currency(amount) do
    {rest, tail} = String.split_at(amount, -4)

    cond do
      String.ends_with?(amount, @currency_symbols) ->
        amount |> String.slice(0..-2//1) |> String.trim()

      currency_code?(tail) ->
        String.trim(rest)

      true ->
        amount
    end
  end

  defp currency_code?(" " <> code), do: code_length(code) == 3 and byte_size(code) == 3
  defp currency_code?(_tail), do: false

  defp code_length(string) do
    string
    |> String.to_charlist()
    |> Enum.take_while(&(&1 in ?A..?Z))
    |> length()
    |> min(3)
  end

  defp accounting_sign("(" <> rest) do
    if String.ends_with?(rest, ")") do
      {"-", rest |> String.trim_trailing(")") |> String.trim()}
    else
      {"", "(" <> rest}
    end
  end

  defp accounting_sign(value), do: {"", value}

  defp leading_sign(<<sign, rest::binary>>) when sign in [?-, ?+],
    do: {<<sign>>, String.trim_leading(rest)}

  defp leading_sign(value), do: {"", value}

  defp restore_value({:error, {:not_a_number, _stripped}}, value),
    do: {:error, {:not_a_number, value}}

  defp restore_value(result, _value), do: result

  defp parse_number(%Decimal{} = d, _separators), do: {:ok, d}
  defp parse_number(value, _separators) when is_integer(value), do: {:ok, Decimal.new(value)}
  defp parse_number(value, _separators) when is_float(value), do: {:ok, Decimal.from_float(value)}

  defp parse_number(value, separators) when is_binary(value) do
    normalised =
      value
      |> String.trim()
      |> String.replace(separators.thousands, "")
      |> String.replace(separators.decimal, ".")

    case Decimal.parse(normalised) do
      {decimal, ""} ->
        {:ok, decimal}

      _ ->
        {:error, {:not_a_number, value}}
    end
  end

  defp parse_number(value, _separators), do: {:error, {:not_a_number, value}}

  defp separators(:en), do: %{decimal: ".", thousands: ","}
  defp separators(:de), do: %{decimal: ",", thousands: "."}
  defp separators(locale), do: raise(ArgumentError, "unknown locale: #{inspect(locale)}")

  # date

  @spec date(term(), [DateParser.opt()]) ::
          {:ok, Date.t()} | {:error, {:not_a_date, term()}}

  def date(value, opts \\ []), do: DateParser.parse(value, opts)

  @spec date!(term(), [DateParser.opt()]) :: Date.t()

  def date!(value, opts \\ []) do
    case date(value, opts) do
      {:ok, date} ->
        date

      {:error, reason} ->
        raise ArgumentError, "cannot parse #{inspect(value)} as a date: #{inspect(reason)}"
    end
  end

  @spec datetime(term(), [DateParser.opt()]) ::
          {:ok, NaiveDateTime.t()} | {:error, {:not_a_datetime, term()}}

  def datetime(value, opts \\ []), do: DateParser.parse_datetime(value, opts)

  @spec datetime!(term(), [DateParser.opt()]) :: NaiveDateTime.t()

  def datetime!(value, opts \\ []) do
    case datetime(value, opts) do
      {:ok, naive} ->
        naive

      {:error, reason} ->
        raise ArgumentError, "cannot parse #{inspect(value)} as a datetime: #{inspect(reason)}"
    end
  end

  # boolean

  @spec boolean(term(), keyword()) :: {:ok, boolean()} | {:error, {:not_a_boolean, term()}}

  def boolean(value, opts \\ []) do
    Keyword.validate!(opts, [])

    parse_boolean(value)
  end

  @spec boolean!(term(), keyword()) :: boolean()

  def boolean!(value, opts \\ []) do
    case boolean(value, opts) do
      {:ok, bool} ->
        bool

      {:error, reason} ->
        raise ArgumentError, "cannot parse #{inspect(value)} as a boolean: #{inspect(reason)}"
    end
  end

  defp parse_boolean(value) when is_boolean(value), do: {:ok, value}

  defp parse_boolean(value) when is_binary(value) do
    normalised_value = normalise(value)

    case normalised_value do
      normalised_value when normalised_value in ["true", "1", "yes", "y"] -> {:ok, true}
      normalised_value when normalised_value in ["false", "0", "no", "n"] -> {:ok, false}
      _ -> {:error, {:not_a_boolean, value}}
    end
  end

  defp parse_boolean(1), do: {:ok, true}
  defp parse_boolean(0), do: {:ok, false}
  defp parse_boolean(value), do: {:error, {:not_a_boolean, value}}

  # integer

  @spec integer(term(), keyword()) :: {:ok, integer()} | {:error, {:not_an_integer, term()}}

  def integer(value, opts \\ []) do
    Keyword.validate!(opts, [])

    parse_integer(value)
  end

  @spec integer!(term(), keyword()) :: integer()

  def integer!(value, opts \\ []) do
    case integer(value, opts) do
      {:ok, int} ->
        int

      {:error, reason} ->
        raise ArgumentError, "cannot parse #{inspect(value)} as an integer: #{inspect(reason)}"
    end
  end

  defp parse_integer(value) when is_integer(value), do: {:ok, value}

  defp parse_integer(value) when is_binary(value) do
    normalised_value = normalise(value)

    case Integer.parse(normalised_value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, {:not_an_integer, value}}
    end
  end

  defp parse_integer(value), do: {:error, {:not_an_integer, value}}
end
