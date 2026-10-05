defmodule Refract.Privacy.Noise do
  alias Refract.Privacy.Keyed
  alias Refract.Privacy.Keyring

  @seed_range Integer.pow(2, 256)

  @type value :: number() | Decimal.t()

  @type opt ::
          {:seed, String.Chars.t()}
          | {:domain, Keyring.domain()}
          | {:keyring, Keyring.t()}
          | {:round, non_neg_integer()}

  @spec relative(value(), number(), [opt()]) :: value()

  def relative(value, fraction, opts) do
    opts = Keyword.validate!(opts, [:seed, :domain, :keyring, :round])

    seed = Keyword.fetch!(opts, :seed)
    domain = Keyword.fetch!(opts, :domain)
    keyring = Keyword.fetch!(opts, :keyring)
    round = Keyword.get(opts, :round)

    validate_amount(fraction)

    factor =
      seed
      |> spread(domain, keyring)
      |> Decimal.mult(to_decimal(fraction))
      |> Decimal.add(1)

    value
    |> to_decimal()
    |> Decimal.mult(factor)
    |> from_decimal(value, round)
  end

  @spec absolute(value(), number(), [opt()]) :: value()

  def absolute(value, amount, opts) do
    opts = Keyword.validate!(opts, [:seed, :domain, :keyring, :round])

    seed = Keyword.fetch!(opts, :seed)
    domain = Keyword.fetch!(opts, :domain)
    keyring = Keyword.fetch!(opts, :keyring)
    round = Keyword.get(opts, :round)

    validate_amount(amount)

    shift =
      seed
      |> spread(domain, keyring)
      |> Decimal.mult(to_decimal(amount))

    value
    |> to_decimal()
    |> Decimal.add(shift)
    |> from_decimal(value, round)
  end

  defp spread(seed, domain, keyring) do
    seed
    |> Keyed.integer(domain, keyring)
    |> Decimal.new()
    |> Decimal.div(@seed_range)
    |> Decimal.mult(2)
    |> Decimal.sub(1)
  end

  defp validate_amount(amount) when is_number(amount) and amount >= 0, do: :ok

  defp validate_amount(amount) do
    raise ArgumentError, "noise amount must be a non negative number, got: #{inspect(amount)}"
  end

  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp to_decimal(value), do: raise(ArgumentError, "noise needs a number, got: #{inspect(value)}")

  defp from_decimal(shifted, %Decimal{exp: exp}, nil), do: Decimal.round(shifted, max(-exp, 0))
  defp from_decimal(shifted, %Decimal{}, round), do: Decimal.round(shifted, round)

  defp from_decimal(shifted, value, _round) when is_integer(value),
    do: shifted |> Decimal.round(0) |> Decimal.to_integer()

  defp from_decimal(shifted, value, nil) when is_float(value), do: Decimal.to_float(shifted)

  defp from_decimal(shifted, value, round) when is_float(value),
    do: shifted |> Decimal.round(round) |> Decimal.to_float()
end
