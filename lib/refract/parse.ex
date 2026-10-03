defmodule Refract.Parse do
  alias Refract.Parse.Date, as: DateParser

  import Refract.String.Utils, only: [normalise: 1]

  @type locale :: :en | :de

  @type number_opt :: {:locale, locale()}

  # number

  @spec number(term(), [number_opt()]) :: {:ok, Decimal.t()} | {:error, {:not_a_number, term()}}

  def number(value, opts \\ []) do
    opts = Keyword.validate!(opts, locale: :en)
    seperator = seperators(Keyword.fetch!(opts, :locale))

    parse_number(value, seperator)
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

  defp parse_number(%Decimal{} = d, _seperators), do: {:ok, d}
  defp parse_number(value, _seperators) when is_integer(value), do: {:ok, Decimal.new(value)}
  defp parse_number(value, _seperators) when is_float(value), do: {:ok, Decimal.from_float(value)}

  defp parse_number(value, seperators) when is_binary(value) do
    normalised =
      value
      |> String.trim()
      |> String.replace(seperators.thousands, "")
      |> String.replace(seperators.decimal, ".")

    case Decimal.parse(normalised) do
      {decimal, ""} ->
        {:ok, decimal}

      _ ->
        {:error, {:not_a_number, value}}
    end
  end

  defp parse_number(value, _seperators), do: {:error, {:not_a_number, value}}

  defp seperators(:en), do: %{decimal: ".", thousands: ","}
  defp seperators(:de), do: %{decimal: ",", thousands: "."}
  defp seperators(locale), do: raise(ArgumentError, "unknown locale: #{inspect(locale)}")

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
