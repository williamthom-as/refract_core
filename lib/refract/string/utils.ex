defmodule Refract.String.Utils do
  @spec blank?(term()) :: boolean()

  def blank?(value) when is_binary(value), do: String.trim(value) == ""
  def blank?(nil), do: true
  def blank?(_), do: false
end
