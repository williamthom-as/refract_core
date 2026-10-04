defmodule Refract.Privacy.Gen do
  alias Refract.Privacy.Keyed
  alias Refract.Privacy.Keyring

  @type opt :: {:length, pos_integer()} | {:domain, Keyring.domain()} | {:keyring, Keyring.t()}

  @spec digits(String.Chars.t(), [opt()]) :: String.t()

  def digits(value, opts) do
    opts = Keyword.validate!(opts, [:length, :domain, :keyring])

    length = Keyword.fetch!(opts, :length)
    domain = Keyword.fetch!(opts, :domain)
    keyring = Keyword.fetch!(opts, :keyring)

    validate_length(length, 76)

    value
    |> Keyed.integer(domain, keyring)
    |> rem(Integer.pow(10, length))
    |> Integer.to_string()
    |> String.pad_leading(length, "0")
  end

  @spec hex(String.Chars.t(), [opt()]) :: String.t()

  def hex(value, opts) do
    opts = Keyword.validate!(opts, [:length, :domain, :keyring])

    length = Keyword.fetch!(opts, :length)
    domain = Keyword.fetch!(opts, :domain)
    keyring = Keyword.fetch!(opts, :keyring)

    validate_length(length, 64)

    value
    |> Keyed.bytes(domain, keyring)
    |> Base.encode16(case: :lower)
    |> binary_part(0, length)
  end

  @spec guid(String.Chars.t(), [opt()]) :: String.t()

  def guid(value, opts) do
    opts = Keyword.validate!(opts, [:domain, :keyring])

    domain = Keyword.fetch!(opts, :domain)
    keyring = Keyword.fetch!(opts, :keyring)

    value
    |> Keyed.bytes(domain, keyring)
    |> to_guid()
  end

  defp to_guid(<<a::48, _version::4, b::12, _variant::2, c::62, _rest::binary>>) do
    <<p1::binary-8, p2::binary-4, p3::binary-4, p4::binary-4, p5::binary-12>> =
      Base.encode16(<<a::48, 4::4, b::12, 2::2, c::62>>, case: :lower)

    Enum.join([p1, p2, p3, p4, p5], "-")
  end

  defp validate_length(length, max) when is_integer(length) and length > 0 and length <= max,
    do: :ok

  defp validate_length(length, max),
    do: raise(ArgumentError, "length must be 1 to #{max}, got: #{inspect(length)}")
end
