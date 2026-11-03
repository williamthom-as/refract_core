defmodule Refract.Table.ColumnNames do
  @moduledoc "row keys a header row has normalised to be valid/unique"

  import Refract.String.Utils, only: [header_cell: 1]

  @nil_col_prefix "col"

  @doc """
  Row keys for header row after undergoing a normalisation. all cells are trimmed and unquoted,
  any blank cells get named `col_<index>` (from 0) if any repeated names they get numbered from 2

      iex> Refract.Table.ColumnNames.from([" Customer ID ", "Name", "", "Balance", "Balance"])
      ["Customer ID", "Name", "col_2", "Balance", "Balance_2"]
  """
  @spec from([Refract.cell()]) :: [String.t()]

  def from(header) do
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

  @doc """
  a raw row as a row map under those keys

      iex> Refract.Table.ColumnNames.to_row(["id", "name"], ["1", "alice"])
      %{"id" => "1", "name" => "alice"}
  """
  @spec to_row([String.t()], [Refract.cell()]) :: Refract.row()

  def to_row(names, raw_row) do
    names
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
