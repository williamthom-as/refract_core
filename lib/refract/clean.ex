defmodule Refract.Clean do
  @moduledoc """

  funs to clean up strings, like whitespace and control characters.
  if the value is not a string, returns it unchanged.

      iex> Refract.Clean.normalise_whitespace("  big   red\tapple ")
      "big red apple"

      iex> Refract.Clean.strip_control_characters("ap\u200bple")
      "apple"
  """

  @spec normalise_whitespace(term()) :: term()

  def normalise_whitespace(value) when is_binary(value) do
    value
    |> String.split(~r/\s+/u, trim: true)
    |> Enum.join(" ")
  end

  def normalise_whitespace(value), do: value

  @spec strip_control_characters(term()) :: term()

  def strip_control_characters(value) when is_binary(value) do
    String.replace(value, ~r/(?![\t\n\r])[\p{Cc}\p{Cf}]/u, "")
  end

  def strip_control_characters(value), do: value
end
