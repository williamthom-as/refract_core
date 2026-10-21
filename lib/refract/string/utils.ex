defmodule Refract.String.Utils do
  @moduledoc false

  @spec blank?(term()) :: boolean()

  def blank?(value) when is_binary(value), do: String.trim(value) == ""
  def blank?(nil), do: true
  def blank?(_), do: false

  @spec blank_line?([term()]) :: boolean()

  def blank_line?(line), do: Enum.all?(line, &blank?/1)

  @spec normalise(term()) :: term()

  def normalise(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  def normalise(value) when is_struct(value, Regex), do: value

  def normalise(nil), do: nil

  @spec header_cell(term()) :: String.t() | nil

  def header_cell(nil), do: nil

  def header_cell(cell) do
    cell
    |> to_string()
    |> String.trim()
    |> unquote_cell()
    |> blank_to_nil()
  end

  defp unquote_cell(cell) do
    if String.starts_with?(cell, "\"") and String.ends_with?(cell, "\"") do
      String.slice(cell, 1..-2//1)
    else
      cell
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(cell), do: cell

  @spec text(term()) :: String.t() | nil

  def text(nil), do: nil
  def text(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  def text(%Date{} = value), do: Date.to_iso8601(value)
  def text(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  def text(%Time{} = value), do: Time.to_iso8601(value)
  def text(value), do: to_string(value)
end
