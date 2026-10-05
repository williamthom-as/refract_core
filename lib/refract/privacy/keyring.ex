defmodule Refract.Privacy.Keyring do
  @moduledoc """
  handles root secrets by version, plus a key per domain derived from root secret.
  highest version is current, but to pin a domain to an older version use `pins:`.

      keyring = Refract.Privacy.Keyring.from_provider!(Refract.Privacy.KeyProvider.Env, [])
      keyring = Refract.Privacy.Keyring.new!(keys: %{1 => root}, pins: %{instance_id: 1})
  """

  @type version :: pos_integer()

  @type domain :: atom() | String.t()

  @type opt ::
          {:keys, %{version() => binary()}}
          | {:pins, %{domain() => version()}}

  @opaque t :: %__MODULE__{
            keys: %{version() => binary()},
            pins: %{String.t() => version()},
            current: version()
          }

  defstruct [:keys, :pins, :current]

  @spec new!([opt()]) :: t()

  @spec from_provider!(module(), keyword(), [{:pins, %{domain() => version()}}]) :: t()

  @spec key(t(), domain()) :: {version(), binary()}

  def new!(opts) do
    opts = Keyword.validate!(opts, [:keys, pins: %{}])

    keys = Keyword.fetch!(opts, :keys)
    pins = Keyword.fetch!(opts, :pins)

    validate_keys!(keys)

    validate_pins!(pins, keys)

    converted_pins =
      Map.new(pins, fn {domain, version} ->
        {to_string(domain), version}
      end)

    current = keys |> Map.keys() |> Enum.max()

    %__MODULE__{keys: keys, pins: converted_pins, current: current}
  end

  def from_provider!(provider, provider_opts, opts \\ []) do
    keys =
      case provider.fetch(provider_opts) do
        {:ok, keys} ->
          keys

        {:error, reason} ->
          raise ArgumentError,
                "failed to fetch keys from #{inspect(provider)}: #{inspect(reason)}"
      end

    new!(Keyword.merge(opts, keys: keys))
  end

  def key(%__MODULE__{keys: keys, pins: pins, current: current}, domain) do
    domain = to_string(domain)

    version = Map.get(pins, domain, current)
    root = Map.fetch!(keys, version)

    {version, :crypto.mac(:hmac, :sha256, root, "refract/" <> domain)}
  end

  defp validate_keys!(keys) do
    if map_size(keys) == 0 do
      raise ArgumentError, "no keys provided"
    end

    for {version, key} <- keys do
      unless is_integer(version) and version > 0 do
        raise ArgumentError, "invalid version #{inspect(version)}"
      end

      unless is_binary(key) and byte_size(key) == 32 do
        raise ArgumentError, "key for version #{version} must be a 32 byte binary"
      end
    end
  end

  defp validate_pins!(pins, keys) do
    for {domain, version} <- pins do
      unless is_integer(version) and version > 0 do
        raise ArgumentError,
              "invalid pinned version #{inspect(version)} for domain #{inspect(domain)}"
      end

      unless Map.has_key?(keys, version) do
        raise ArgumentError,
              "pinned version #{version} for domain #{inspect(domain)} does not exist in keys"
      end
    end
  end

  defimpl Inspect do
    def inspect(keyring, _opts),
      do:
        "#Refract.Privacy.Keyring<versions: #{inspect(keyring.keys |> Map.keys() |> Enum.sort())}>"
  end
end
