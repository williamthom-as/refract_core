defmodule Refract.Utils do
  @spec truthy?(term()) :: boolean()

  def truthy?(value), do: value not in [nil, false]
end
