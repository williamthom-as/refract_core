defmodule Refract.Validate.Unique do
  @moduledoc false

  import Refract.String.Utils, only: [blank?: 1]

  alias Refract.Validate.CrossRow.Ctx
  alias Refract.Validate.Issue
  alias Refract.Validate.Seen

  @enforce_keys [:columns, :seen]

  defstruct [:columns, :seen]

  @type t :: %__MODULE__{columns: [String.t(), ...], seen: Seen.t() | :full}

  @spec new([String.t(), ...], pos_integer()) :: t()

  def new(columns, max), do: %__MODULE__{columns: columns, seen: Seen.new(max)}

  @spec check_row(t(), Refract.row(), Ctx.t()) :: {[Issue.t()], t()}

  def check_row(%__MODULE__{seen: :full} = unique, _row, _ctx), do: {[], unique}

  def check_row(%__MODULE__{columns: columns} = unique, row, %Ctx{failed: failed} = ctx) do
    cells = Enum.map(columns, &Map.get(row, &1))

    cells
    |> comparable?(columns, failed)
    |> compare_with_seen(unique, cells, ctx)
  end

  defp comparable?([cell], [column], failed),
    do: not blank?(cell) and not MapSet.member?(failed, column)

  defp comparable?(cells, _columns, _failed), do: not Enum.any?(cells, &blank?/1)

  defp compare_with_seen(false, unique, _cells, _ctx), do: {[], unique}

  defp compare_with_seen(true, %__MODULE__{seen: seen} = unique, cells, %Ctx{line: line} = ctx) do
    seen
    |> Seen.put(seen_key(cells), line)
    |> handle_put(unique, cells, ctx)
  end

  defp seen_key([cell]), do: cell

  defp seen_key(cells), do: List.to_tuple(cells)

  defp handle_put({:new, seen}, unique, _cells, _ctx), do: {[], %{unique | seen: seen}}

  defp handle_put({:seen, first_line, seen}, %__MODULE__{columns: columns} = unique, cells, ctx),
    do: {[unique_issue(columns, cells, first_line, ctx)], %{unique | seen: seen}}

  defp handle_put(:full, %__MODULE__{columns: columns} = unique, _cells, ctx),
    do: {[max_tracked_issue(columns, ctx)], %{unique | seen: :full}}

  defp unique_issue([column], [cell], first_line, %Ctx{line: line, values: values}) do
    %Issue{
      line: line,
      column: column,
      rule: :unique,
      first_line: first_line,
      value: Issue.shown(values, cell)
    }
  end

  defp unique_issue(columns, _cells, first_line, %Ctx{line: line}),
    do: %Issue{line: line, rule: {:unique, columns}, first_line: first_line}

  defp max_tracked_issue([column], %Ctx{line: line}),
    do: %Issue{line: line, column: column, rule: {:max_tracked, :unique}}

  defp max_tracked_issue(columns, %Ctx{line: line}),
    do: %Issue{line: line, rule: {:max_tracked, {:unique, columns}}}
end
