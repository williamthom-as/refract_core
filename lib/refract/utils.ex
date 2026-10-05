defmodule Refract.Utils do
  @moduledoc false

  @spec truthy?(term()) :: boolean()

  def truthy?(value), do: value not in [nil, false]
end
