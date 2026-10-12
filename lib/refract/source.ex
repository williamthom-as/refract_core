defmodule Refract.Source do
  @moduledoc false

  @spec path(Refract.source()) :: Path.t() | nil

  def path(path) when is_binary(path), do: path
  def path(_source), do: nil

  @spec name(Refract.source()) :: String.t() | nil

  def name(path) when is_binary(path), do: Path.basename(path)
  def name(_source), do: nil

  @spec extension(Refract.source()) :: String.t() | nil

  def extension(path) when is_binary(path) do
    path
    |> Path.extname()
    |> String.trim_leading(".")
    |> String.downcase()
  end

  def extension(_source), do: nil

  @spec size(Refract.source()) :: {:ok, non_neg_integer() | :unknown} | {:error, term()}

  def size({:string, string}), do: {:ok, byte_size(string)}
  def size({:stream, _chunks}), do: {:ok, :unknown}

  def size(path) when is_binary(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> {:ok, size}
      {:error, reason} -> {:error, reason}
    end
  end
end
