defmodule Refract.CSV.LocateTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  alias Refract.CSV
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

  @rows [
    %{
      "vendor" => "ABC123",
      "sku" => "78632478",
      "item" => "apple",
      "cost_per_kg" => "1.5",
      "kg" => "2",
      "total" => "3"
    },
    %{
      "vendor" => "DEF567",
      "sku" => "12319082",
      "item" => "oarnge",
      "cost_per_kg" => "2.5",
      "kg" => "2",
      "total" => "5"
    },
    %{
      "vendor" => "DEF567",
      "sku" => "90834222",
      "item" => "pear",
      "cost_per_kg" => "0.5",
      "kg" => "3",
      "total" => "1.5"
    }
  ]

  @subtotal %{
    "vendor" => "",
    "sku" => "",
    "item" => "Subtotal",
    "cost_per_kg" => "",
    "kg" => "",
    "total" => "8"
  }

  defp shape(name), do: Path.join(@shapes, name)

  defp invoice_spec(opts \\ []) do
    defaults = [
      header: [columns: @columns, required: ["sku", "total"], min_matches: 4],
      row: [match: %{"sku" => :integer, "total" => :number}],
      stop: [:blank, {:contains, ~r/invoice total/i}],
      max_misses: 1
    ]

    Table.spec(Keyword.merge(defaults, opts))
  end

  describe "locate/3" do
    test "finds a shifted header and streams the rows under it" do
      assert {:ok, table} = CSV.locate(shape("messy_invoice.csv"), invoice_spec())
      assert is_struct(table, Table)

      assert table.header_row == 10
      assert table.header == ["vendor", "sku", "item", "cost_per_kg", "kg", "total"]

      assert table.columns == %{
               "vendor" => 1,
               "sku" => 3,
               "item" => 4,
               "cost_per_kg" => 5,
               "kg" => 6,
               "total" => 7
             }

      assert Enum.to_list(table.rows) == @rows
    end

    test "renamed vendor headers give the same table" do
      assert {:ok, table} = CSV.locate(shape("messy_invoice_renamed.csv"), invoice_spec())

      assert table.header_row == 10
      assert Enum.to_list(table.rows) == @rows
    end

    test "a decoy row is not taken for the header" do
      assert {:ok, table} = CSV.locate(shape("messy_invoice_decoy.csv"), invoice_spec())

      assert table.header_row == 10
    end

    test "the blank line ends a table even with a repeated header below it" do
      assert {:ok, table} = CSV.locate(shape("repeated_header.csv"), invoice_spec())

      assert Enum.to_list(table.rows) == Enum.take(@rows, 2)
    end

    test "open errors pass through" do
      assert {:error, :enoent} = CSV.locate(shape("missing.csv"), invoice_spec())
    end
  end

  describe "locate/3 misses" do
    test "on_miss: :skip drops miss rows by default" do
      assert {:ok, table} = CSV.locate(shape("messy_invoice.csv"), invoice_spec())

      refute @subtotal in Enum.to_list(table.rows)
    end

    test "on_miss: :keep keeps miss rows" do
      assert {:ok, table} =
               CSV.locate(shape("messy_invoice.csv"), invoice_spec(), on_miss: :keep)

      assert Enum.to_list(table.rows) == [
               Enum.at(@rows, 0),
               Enum.at(@rows, 1),
               @subtotal,
               Enum.at(@rows, 2)
             ]
    end

    test "max_misses: 0 ends the table at the first miss" do
      assert {:ok, table} = CSV.locate(shape("messy_invoice.csv"), invoice_spec(max_misses: 0))

      assert Enum.to_list(table.rows) == Enum.take(@rows, 2)
    end

    test "raises on an unknown on_miss" do
      assert_raise ArgumentError, fn ->
        CSV.locate(shape("messy_invoice.csv"), invoice_spec(), on_miss: :ignore)
      end
    end
  end

  describe "locate/3 header not found" do
    test "reports the closest row and what it was missing" do
      csv = "junk\nVendor,SKU,Item,Kg\n1,2,3,4\n"

      assert {:error, {:header_not_found, best}} = CSV.locate({:string, csv}, invoice_spec())
      assert best.row == 2
      assert Enum.sort(best.matched) == ["item", "kg", "sku", "vendor"]
      assert best.missing == ["total"]
    end

    test "a file with no table is an error" do
      assert {:error, {:header_not_found, best}} =
               CSV.locate(shape("no_table.csv"), invoice_spec())

      assert best.matched == []
      assert Enum.sort(best.missing) == ["sku", "total"]
    end

    test "only searches the first within: lines" do
      assert {:error, {:header_not_found, _}} =
               CSV.locate(shape("messy_invoice.csv"), invoice_spec(), within: 9)

      assert {:ok, _} = CSV.locate(shape("messy_invoice.csv"), invoice_spec(), within: 10)
    end
  end

  describe "locate/3 laziness" do
    test "reads no further than within: to find the header, then streams" do
      lines =
        Stream.concat(
          ["sku,total\n", "1,2\n"],
          Stream.map(["boom\n"], fn _ -> raise "read too early" end)
        )

      spec = Table.spec(header: [columns: %{"sku" => ["sku"], "total" => ["total"]}])

      assert {:ok, table} = CSV.locate({:stream, lines}, spec, within: 2)
      assert Enum.take(table.rows, 1) == [%{"sku" => "1", "total" => "2"}]
    end
  end
end
