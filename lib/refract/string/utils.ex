defmodule Refract.String.Utils do
  @spec blank?(term()) :: boolean()

  def blank?(value) when is_binary(value), do: String.trim(value) == ""
  def blank?(nil), do: true
  def blank?(_), do: false

  @spec normalise(term()) :: term()

  def normalise(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  def normalise(value) when is_struct(value, Regex), do: value

  def normalise(nil), do: nil
end
