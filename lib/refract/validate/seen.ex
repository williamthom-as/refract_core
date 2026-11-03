defmodule Refract.Validate.Seen do
  @moduledoc false

  import Refract.ArgValidator, only: [validate_positive_integer!: 2]

  @enforce_keys [:max]

  defstruct [:max, lines: %{}]

  @type t :: %__MODULE__{
          max: pos_integer(),
          lines: %{term() => pos_integer()}
        }

  @spec new(pos_integer()) :: t()

  def new(max) do
    validate_positive_integer!(max, :max)

    %__MODULE__{max: max}
  end

  @spec put(t(), term(), pos_integer()) :: {:new, t()} | {:seen, pos_integer(), t()} | :full

  def put(%__MODULE__{lines: lines} = seen, key, line) do
    lines
    |> Map.fetch(key)
    |> store(seen, key, line)
  end

  defp store({:ok, first_line}, seen, _key, _line), do: {:seen, first_line, seen}

  defp store(:error, %__MODULE__{lines: lines, max: max}, _key, _line)
       when map_size(lines) >= max do
    :full
  end

  defp store(:error, %__MODULE__{lines: lines} = seen, key, line),
    do: {:new, %{seen | lines: Map.put(lines, key, line)}}
end
