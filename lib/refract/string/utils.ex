defmodule Refract.String.Utils do
  @spec blank?(term()) :: boolean()

  def blank?(value) when is_binary(value), do: String.trim(value) == ""
  def blank?(nil), do: true
  def blank?(_), do: false

  @spec normalise_search_value(term()) :: term()

  def normalise_search_value(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  def normalise_search_value(value) when is_struct(value, Regex), do: value

  def normalise_search_value(nil), do: nil
end
