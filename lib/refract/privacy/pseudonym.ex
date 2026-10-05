defmodule Refract.Privacy.Pseudonym do
  @moduledoc """
  provides reversible pseudonyms for a value, used for joinable ids.
  you can swap a value for a fake one and keep same format.

  uses ff1 under the hood, so same key, domain and value always give the
  same output and two values never share one. assuming you have the same
  key you can always get a transformed value back.

  `canonical:` links spelling variants. under 1,000,000 possible values
  is refused unless `min_domain:` is lowered

      Refract.Privacy.Pseudonym.apply!("1234567890", :instance_id, keyring)
      Refract.Privacy.Pseudonym.apply!("0abc123def4567890", :instance_id, keyring, alphabet: :hex)
      Refract.Privacy.Pseudonym.reverse!(pseudonym, :instance_id, keyring)
  """

  alias Refract.Privacy.Keyring

  alias Refract.Privacy.Pseudonym.FF1

  @type alphabet :: :digits | :hex | :base36 | :alphanumeric | String.t()

  @type opt ::
          {:alphabet, alphabet()}
          | {:canonical, (String.t() -> String.t())}
          | {:min_domain, non_neg_integer()}

  @type error :: FF1.error() | {:not_a_string, term()}

  @spec apply(term(), Keyring.domain(), Keyring.t(), [opt()]) ::
          {:ok, String.t()} | {:error, error()}

  def apply(value, domain, keyring, opts \\ [])

  def apply(value, domain, keyring, opts) when is_binary(value) do
    opts = Keyword.validate!(opts, alphabet: :digits, canonical: & &1, min_domain: 1_000_000)

    canonical = Keyword.fetch!(opts, :canonical)
    alphabet = opts |> Keyword.fetch!(:alphabet) |> alphabet()
    ff1_opts = Keyword.take(opts, [:min_domain])

    {_version, key} = Keyring.key(keyring, domain)

    FF1.encrypt(key, to_string(domain), alphabet, canonical.(value), ff1_opts)
  end

  def apply(value, _domain, _keyring, _opts), do: {:error, {:not_a_string, value}}

  @spec apply!(term(), Keyring.domain(), Keyring.t(), [opt()]) :: String.t()

  def apply!(value, domain, keyring, opts \\ []) do
    value
    |> __MODULE__.apply(domain, keyring, opts)
    |> unwrap_result()
  end

  @spec reverse(term(), Keyring.domain(), Keyring.t(), [opt()]) ::
          {:ok, String.t()} | {:error, error()}

  def reverse(value, domain, keyring, opts \\ [])

  def reverse(value, domain, keyring, opts) when is_binary(value) do
    opts = Keyword.validate!(opts, alphabet: :digits, canonical: & &1, min_domain: 1_000_000)

    canonical = Keyword.fetch!(opts, :canonical)
    alphabet = opts |> Keyword.fetch!(:alphabet) |> alphabet()
    ff1_opts = Keyword.take(opts, [:min_domain])

    {_version, key} = Keyring.key(keyring, domain)

    FF1.decrypt(key, to_string(domain), alphabet, canonical.(value), ff1_opts)
  end

  def reverse(value, _domain, _keyring, _opts), do: {:error, {:not_a_string, value}}

  @spec reverse!(term(), Keyring.domain(), Keyring.t(), [opt()]) :: String.t()

  def reverse!(value, domain, keyring, opts \\ []) do
    value
    |> __MODULE__.reverse(domain, keyring, opts)
    |> unwrap_result()
  end

  defp unwrap_result({:ok, result}), do: result

  defp unwrap_result({:error, {reason, _detail}}),
    do: raise(ArgumentError, "pseudonym failed: #{reason}")

  defp alphabet(:digits), do: "0123456789"
  defp alphabet(:hex), do: "0123456789abcdef"
  defp alphabet(:base36), do: "0123456789abcdefghijklmnopqrstuvwxyz"

  defp alphabet(:alphanumeric),
    do: "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

  defp alphabet(custom) when is_binary(custom), do: custom
  defp alphabet(other), do: raise(ArgumentError, "unknown alphabet: #{inspect(other)}")
end
