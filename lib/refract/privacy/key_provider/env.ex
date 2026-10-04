defmodule Refract.Privacy.KeyProvider.Env do
  @behaviour Refract.Privacy.KeyProvider

  @impl Refract.Privacy.KeyProvider

  def fetch(opts) do
    opts = Keyword.validate!(opts, prefix: "REFRACT_KEY")
    prefix = Keyword.fetch!(opts, :prefix)

    keys =
      for {^prefix <> "_" <> rest = name, value} <- System.get_env(),
          {version, ""} <- [Integer.parse(rest)] do
        {version, name, value}
      end

    case keys do
      [] -> {:error, {:no_keys, prefix}}
      _ -> decode(keys, %{})
    end
  end

  defp decode([], mapped_keys), do: {:ok, mapped_keys}

  defp decode([{version, name, value} | rest], mapped_keys) do
    case Base.decode64(value) do
      {:ok, bytes} -> decode(rest, Map.put(mapped_keys, version, bytes))
      :error -> {:error, {:invalid_base64, name}}
    end
  end
end
