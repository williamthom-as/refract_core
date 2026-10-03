defmodule Refract.Pseudonym do
  alias Refract.Keyring

  alias Refract.Pseudonym.FF1

  @type alphabet :: :digits | :hex | :base36 | :alphanumeric | String.t()

  @type opt ::
          {:alphabet, alphabet()}
          | {:canonical, (String.t() -> String.t())}
          | {:min_domain, non_neg_integer()}

  @type error :: FF1.error() | {:not_a_string, term()}

  @spec apply(term(), Keyring.domain(), Keyring.t(), [opt()]) ::
          {:ok, String.t()} | {:error, error()}

  def apply(value, domain, keyring)

  def apply(value, domain, keyring, opts \\ [])

  def apply(value, domain, keyring, opts) when is_binary(value) do
    {ff1_opts, opts} = Keyword.split(opts, [:min_domain])

    opts = Keyword.validate!(opts, alphabet: :digits, canonical: & &1)

    canonical = Keyword.fetch!(opts, :canonical)
    alphabet = opts |> Keyword.fetch!(:alphabet) |> alphabet()

    {:ok, key} = fetch_key(keyring, domain)

    FF1.encrypt(key, to_string(domain), alphabet, canonical.(value), ff1_opts)
  end

  def apply(value, _domain, _keyring, _opts), do: {:error, {:not_a_string, value}}

  def apply!(value, domain, keyring, opts \\ []) do
    value
    |> __MODULE__.apply(domain, keyring, opts)
    |> handle_apply_result()
  end

  defp handle_apply_result({:ok, result}), do: result

  defp handle_apply_result({:error, {reason, _detail}}),
    do: raise(ArgumentError, "pseudonym failed: #{reason}")

  # @spec apply!(term(), Keyring.domain(), Keyring.t(), [opt()]) ::
  #         String.t()

  # @spec reverse(term(), Keyring.domain(), Keyring.t(), [opt()]) ::
  #         {:ok, String.t()} | {:error, error()}

  # @spec reverse!(term(), Keyring.domain(), Keyring.t(), [opt()]) ::
  #         String.t()

  defp fetch_key(keyring, domain) do
    {_version, key} = Keyring.key(keyring, domain)

    {:ok, key}
  end

  defp alphabet(:digits), do: "0123456789"
  defp alphabet(:hex), do: "0123456789abcdef"
  defp alphabet(:base36), do: "0123456789abcdefghijklmnopqrstuvwxyz"

  defp alphabet(:alphanumeric),
    do: "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

  defp alphabet(custom) when is_binary(custom), do: custom
  defp alphabet(other), do: raise(ArgumentError, "unknown alphabet:
  #{inspect(other)}")

  defp validate_alphabet(alphabet) when alphabet in [:digits, :hex, :base36, :alphanumeric] do
    :ok
  end

  defp validate_alphabet(alphabet),
    do: raise(ArgumentError, "invalid alphabet: #{inspect(alphabet)}")
end
