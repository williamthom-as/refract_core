defmodule Refract.Table.Concat do
  @moduledoc false

  alias Refract.Table

  @spec run([Table.t()]) :: Table.t()

  def run(tables) do
    validate_tables(tables)

    header =
      tables
      |> Enum.flat_map(fn %Table{header: h} -> h end)
      |> Enum.uniq()

    blank_row = Map.new(header, fn h -> {h, nil} end)

    rows =
      Stream.flat_map(tables, fn %Table{rows: r} ->
        Stream.map(r, &Map.merge(blank_row, &1))
      end)

    Table.new(nil, header, %{}, rows)
  end

  defp validate_tables(tables), do: validate_tables(tables, tables)

  defp validate_tables([], _tables), do: :ok

  defp validate_tables([%Table{} | rest], tables), do: validate_tables(rest, tables)

  defp validate_tables(_rest, _tables), do: raise(ArgumentError, "Expected a list of tables")
end
