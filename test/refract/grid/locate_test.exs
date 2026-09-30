defmodule Refract.Grid.LocateTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  alias Refract.CSV
  alias Refract.Grid
  alias Refract.Table

  @shapes Path.expand("../../fixtures/shapes", __DIR__)

  @columns %{
    "vendor" => ["vendor", "supplier"],
    "sku" => ["sku", "product code"],
    "item" => ["item", "description"],
    "cost_per_kg" => ["cost/kg", "unit price"],
    "kg" => ["kg", "qty"],
    "total" => ["line total", "amount"]
  }

  defp shape(name), do: Path.join(@shapes, name)

  defp load!(source) do
    {:ok, grid} = CSV.load(source)

    grid
  end

  defp invoice_spec(opts \\ []) do
    defaults = [
      header: [columns: @columns, required: ["sku", "total"], min_matches: 4],
      row: [match: %{"sku" => :integer, "total" => :number}],
      stop: [:blank, {:contains, ~r/invoice total/i}],
      max_misses: 1
    ]

    Table.spec(Keyword.merge(defaults, opts))
  end

  defp same_table!(name, opts \\ []) do
    assert {:ok, from_grid} = Grid.locate(load!(shape(name)), invoice_spec(), opts)
    assert {:ok, from_csv} = CSV.locate(shape(name), invoice_spec(), opts)

    assert is_struct(from_grid, Table)

    assert from_grid.header_row == from_csv.header_row
    assert from_grid.header == from_csv.header
    assert from_grid.columns == from_csv.columns

    assert Enum.to_list(from_grid.rows) == Enum.to_list(from_csv.rows)
  end

  describe "locate/3 gives the same table as CSV.locate" do
    test "messy invoice" do
      same_table!("messy_invoice.csv")
    end

    test "renamed headers" do
      same_table!("messy_invoice_renamed.csv")
    end

    test "decoy row" do
      same_table!("messy_invoice_decoy.csv")
    end

    test "repeated header" do
      same_table!("repeated_header.csv")
    end

    test "on_miss: :keep" do
      same_table!("messy_invoice.csv", on_miss: :keep)
    end
  end

  describe "locate/3" do
    test "searches the whole grid by default" do
      junk = String.duplicate("junk\n", 149)
      csv = junk <> "sku,total\n1,2\n"

      spec = Table.spec(header: [columns: %{"sku" => ["sku"], "total" => ["total"]}])

      assert {:error, {:header_not_found, _}} = CSV.locate({:string, csv}, spec)

      assert {:ok, table} = Grid.locate(load!({:string, csv}), spec)

      assert table.header_row == 150
      assert Enum.to_list(table.rows) == [%{"sku" => "1", "total" => "2"}]
    end

    test "within: still limits the search" do
      assert {:error, {:header_not_found, _}} =
               Grid.locate(load!(shape("messy_invoice.csv")), invoice_spec(), within: 9)
    end

    test "a grid with no table reports the closest row" do
      assert {:error, {:header_not_found, best}} =
               Grid.locate(load!(shape("no_table.csv")), invoice_spec())

      assert best.matched == []
      assert Enum.sort(best.missing) == ["sku", "total"]
    end

    test "an empty grid has no table" do
      assert {:error, {:header_not_found, nil}} = Grid.locate(Grid.new([]), invoice_spec())
    end

    test "raises on an unknown on_miss" do
      assert_raise ArgumentError, fn ->
        Grid.locate(load!(shape("messy_invoice.csv")), invoice_spec(), on_miss: :ignore)
      end
    end
  end
end
