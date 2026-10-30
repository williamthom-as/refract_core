defmodule Refract.Utils do
  @moduledoc false

  @spec truthy?(term()) :: boolean()

  def truthy?(value), do: value not in [nil, false]

  @spec exports?(term(), atom(), arity()) :: boolean()

  def exports?(module, fun, arity) when is_atom(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, fun, arity)

  def exports?(_module, _fun, _arity), do: false
end
