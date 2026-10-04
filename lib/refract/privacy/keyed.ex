defmodule Refract.Privacy.Keyed do
  alias Refract.Privacy.Keyring

  @subkey_label "refract/keyed"

  @spec bytes(String.Chars.t(), Keyring.domain(), Keyring.t()) :: <<_::256>>

  def bytes(value, domain, keyring) do
    {_version, key} = Keyring.key(keyring, domain)
    subkey = :crypto.mac(:hmac, :sha256, key, @subkey_label)

    :crypto.mac(:hmac, :sha256, subkey, to_string(value))
  end

  @spec integer(String.Chars.t(), Keyring.domain(), Keyring.t()) :: non_neg_integer()

  def integer(value, domain, keyring),
    do: value |> bytes(domain, keyring) |> :binary.decode_unsigned()
end
