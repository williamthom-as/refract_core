defmodule Refract.Clean do
  @moduledoc """

  funs to clean up strings, like whitespace and control characters.
  if the value is not a string, returns it unchanged.

      iex> Refract.Clean.normalise_whitespace("  big   red\tapple ")
      "big red apple"

      iex> Refract.Clean.strip_control_characters("ap\u200bple")
      "apple"

      iex> Refract.Clean.slug("Unit Price (ex GST)")
      "unit_price_ex_gst"

      iex> Refract.Clean.digits("(02) 9876 5432")
      "0298765432"
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

  @spec slug(term()) :: term()

  def slug(value) when is_binary(value) do
    value
    |> String.normalize(:nfd)
    |> String.replace(~r/(?<=\p{Latin})\p{Mn}+/u, "")
    |> String.normalize(:nfc)
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{M}\p{N}]+/u, "_")
    |> String.trim("_")
  end

  def slug(value), do: value

  @spec digits(term()) :: term()

  def digits(value) when is_binary(value), do: String.replace(value, ~r/[^0-9]+/, "")

  def digits(value), do: value
end
