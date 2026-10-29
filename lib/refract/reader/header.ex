defmodule Refract.Reader.Header do
  @moduledoc false

  import Refract.String.Utils, only: [header_cell: 1]

  @nil_col_prefix "col"

  @spec names([Refract.cell()]) :: [String.t()]

  def names(header) do
    normalised_header =
      Enum.map(header, &header_cell/1)

    reserved =
      Enum.reject(normalised_header, &is_nil/1)
      |> MapSet.new()

    {names, _c} =
      normalised_header
      |> Enum.with_index()
      |> Enum.map_reduce(MapSet.new(), fn {cell, idx}, acc ->
        cleaned_name = if is_nil(cell), do: invalid_col_name(@nil_col_prefix, idx), else: cell

        cleaned_name =
          if MapSet.member?(acc, cleaned_name) do
            normalise_col_name(cleaned_name, 2, acc, reserved)
          else
            cleaned_name
          end

        {cleaned_name, MapSet.put(acc, cleaned_name)}
      end)

    names
  end

  @spec to_row([String.t()], [Refract.cell()]) :: Refract.row()

  def to_row(header, raw_row) do
    header
    |> Enum.zip(raw_row)
    |> Map.new()
  end

  # privates

  # the complexities here come from forced renaming duplicate col headers
  # that could be existing already [a,a,a_2] becomes [a,a_3,a_2] not [a,a_2,a_3]

  defp normalise_col_name(candidate, idx, taken, reserved) do
    temp_candidate = invalid_col_name(candidate, idx)

    if MapSet.member?(taken, temp_candidate) or MapSet.member?(reserved, temp_candidate) do
      normalise_col_name(candidate, idx + 1, taken, reserved)
    else
      temp_candidate
    end
  end

  defp invalid_col_name(existing_name, idx), do: "#{existing_name}_#{idx}"
end
