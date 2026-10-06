defmodule Refract.Comparable do
  @spec of(term()) :: term()

  def of(%Regex{} = regex), do: {:regex, Regex.source(regex), Regex.opts(regex)}
  def of(%_{} = struct), do: struct |> Map.from_struct() |> of()
  def of(map) when is_map(map), do: Map.new(map, fn {key, value} -> {key, of(value)} end)
  def of(list) when is_list(list), do: Enum.map(list, &of/1)
  def of({key, value}), do: {of(key), of(value)}
  def of(value), do: value
end
