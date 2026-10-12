defmodule Refract.File.Utils do
  @moduledoc false

  import Refract.Source, only: [size: 1]

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
