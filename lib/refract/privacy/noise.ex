defmodule Refract.Privacy.Noise do
  @moduledoc """
  shift numbers by a keyed amount, seeded by the entity not the value.
  the same entity shifts the same way every time and numbers keep their
  type

      Refract.Privacy.Noise.relative(cost, 0.05, seed: instance_id, domain: :cost, keyring: keyring)
      Refract.Privacy.Noise.absolute(count, 3, seed: instance_id, domain: :count, keyring: keyring)
  """

  alias Refract.Privacy.Keyed
  alias Refract.Privacy.Keyring

  @seed_range Integer.pow(2, 64)
  @spread_places 18
  @spread_scale Integer.pow(10, 18)
  @max_places 6144

  @type value :: number() | Decimal.t()

  @type opt ::
          {:seed, String.Chars.t()}
          | {:domain, Keyring.domain()}
          | {:keyring, Keyring.t()}
          | {:round, 0..6144}

  @spec relative(value(), number(), [opt()]) :: value()

  def relative(value, fraction, opts) do
    opts = Keyword.validate!(opts, [:seed, :domain, :keyring, :round])

    seed = Keyword.fetch!(opts, :seed)
    domain = Keyword.fetch!(opts, :domain)
    keyring = Keyword.fetch!(opts, :keyring)
    round = Keyword.get(opts, :round)

    validate_amount(fraction)
    validate_round(round)

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
    validate_round(round)

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
    <<top::64, _rest::binary>> = Keyed.bytes(seed, domain, keyring)

    ((2 * top - @seed_range) * @spread_scale)
    |> Bitwise.>>>(64)
    |> to_spread()
  end

  defp to_spread(scaled) when scaled < 0, do: Decimal.new(-1, -scaled, -@spread_places)
  defp to_spread(scaled), do: Decimal.new(1, scaled, -@spread_places)

  defp validate_amount(amount) when is_number(amount) and amount >= 0, do: :ok

  defp validate_amount(amount) do
    raise ArgumentError, "noise amount must be a non negative number, got: #{inspect(amount)}"
  end

  defp validate_round(nil), do: :ok

  defp validate_round(round) when is_integer(round) and round >= 0 and round <= @max_places,
    do: :ok

  defp validate_round(round) do
    raise ArgumentError,
          "round must be an integer from 0 to #{@max_places}, got: #{inspect(round)}"
  end

  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp to_decimal(value), do: raise(ArgumentError, "noise needs a number, got: #{inspect(value)}")

  defp from_decimal(shifted, %Decimal{exp: exp}, nil),
    do: Decimal.round(shifted, min(max(-exp, 0), @max_places))

  defp from_decimal(shifted, %Decimal{}, round), do: Decimal.round(shifted, round)

  defp from_decimal(shifted, value, _round) when is_integer(value),
    do: shifted |> Decimal.round(0) |> Decimal.to_integer()

  defp from_decimal(shifted, value, nil) when is_float(value), do: Decimal.to_float(shifted)

  defp from_decimal(shifted, value, round) when is_float(value),
    do: shifted |> Decimal.round(round) |> Decimal.to_float()
end
