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

  defp validate_tables(tables) when is_list(tables) do
    if not Enum.all?(tables, &is_struct(&1, Table)) do
      raise ArgumentError, "expected a list of tables, got: #{inspect(tables)}"
    end
  end

  defp validate_tables(tables) do
    raise ArgumentError, "expected a list of tables, got: #{inspect(tables)}"
  end
end
