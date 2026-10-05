defmodule Refract.Grid.Classify do
  @moduledoc false

  alias Refract.Grid
  alias Refract.Table
  alias Refract.Table.Spec
  alias Refract.Table.Spec.Header
  alias Refract.Table.Spec.Row

  @type class :: :header | :row | :other

  @type why ::
          :header_matched
          | :row_matched
          | {:header_miss, Header.miss()}
          | {:row_miss, Row.miss()}

  @typep entry :: %{
           line: pos_integer(),
           class: class(),
           value: Header.positions() | Refract.row() | Refract.raw_row(),
           why: why()
         }

  @type classified ::
          {:header, pos_integer(), Header.positions()}
          | {:row, pos_integer(), Refract.row()}
          | {:other, pos_integer(), Refract.raw_row()}

  @type explained :: %{line: pos_integer(), class: class(), why: why()}

  @spec classify(Grid.t(), Spec.t()) :: [classified()]

  def classify(%Grid{} = grid, %Spec{} = spec) do
    grid
    |> walk(spec)
    |> Enum.map(fn %{line: line, class: class, value: value} ->
      {class, line, value}
    end)
  end

  @spec explain(Grid.t(), Spec.t()) :: [explained()]

  def explain(%Grid{} = grid, %Spec{} = spec) do
    grid
    |> walk(spec)
    |> Enum.map(fn %{line: line, class: class, why: why} ->
      %{line: line, class: class, why: why}
    end)
  end

  @spec walk(Grid.t(), Spec.t()) :: [entry()]

  defp walk(%Grid{} = grid, %Spec{} = spec) do
    {entries, _positions} =
      grid
      |> Grid.rows_as_list()
      |> Enum.with_index(1)
      |> Enum.map_reduce(nil, fn {row, line}, positions ->
        spec
        |> Table.match_header(row)
        |> judge_header(row, line, positions, spec)
      end)

    entries
  end

  defp judge_header({:ok, header_positions}, _row, line, _positions, _spec) do
    entry = %{
      line: line,
      class: :header,
      value: header_positions,
      why: :header_matched
    }

    {entry, header_positions}
  end

  # havent hit header yet, no positions yet

  defp judge_header({:error, miss}, row, line, nil, _spec) do
    entry = %{
      line: line,
      class: :other,
      value: row,
      why: {:header_miss, miss}
    }

    {entry, nil}
  end

  defp judge_header({:error, _miss}, row, line, positions, spec) do
    mapped_row = Table.ordered_row(row, positions)

    spec
    |> Table.match_row(mapped_row)
    |> judge_row(row, mapped_row, line, positions)
  end

  defp judge_row(:ok, _row, mapped_row, line, positions) do
    entry = %{
      line: line,
      class: :row,
      value: mapped_row,
      why: :row_matched
    }

    {entry, positions}
  end

  defp judge_row({:error, miss}, row, _mapped_row, line, positions) do
    entry = %{
      line: line,
      class: :other,
      value: row,
      why: {:row_miss, miss}
    }

    {entry, positions}
  end
end
