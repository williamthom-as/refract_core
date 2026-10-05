defmodule Refract.File.Utils do
  @moduledoc false

  @spec size(source :: Refract.source()) ::
          {:ok, non_neg_integer()} | {:ok, :unknown} | {:error, term()}

  def size({:string, string}) do
    {:ok, byte_size(string)}
  end

  def size({:stream, _stream}) do
    {:ok, :unknown}
  end

  def size(path) when is_binary(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> {:ok, size}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec size_check(source :: Refract.source(), max_size :: non_neg_integer(), opts :: keyword()) ::
          :ok | {:error, term()}

  def size_check(source, max_size, opts \\ []) do
    streams_allowed = Keyword.get(opts, :streams_allowed, false)

    case {size(source), streams_allowed} do
      {{:ok, :unknown}, true} -> :ok
      {{:ok, :unknown}, false} -> {:error, {:stream_not_allowed, source}}
      {{:ok, size}, _} when size <= max_size -> :ok
      {{:ok, _size}, _} -> {:error, {:max_bytes_exceeded, max_size}}
      {{:error, reason}, _} -> {:error, reason}
    end
  end
end
