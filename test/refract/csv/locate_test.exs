defmodule Refract.CSV.LocateTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  alias Refract.CSV
  alias Refract.Table

  @layouts Path.expand("../../fixtures/layouts", __DIR__)

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

  defp layout(name), do: Path.join(@layouts, name)

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
      assert {:ok, table} = CSV.locate(layout("messy_invoice.csv"), invoice_spec())
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
      assert {:ok, table} = CSV.locate(layout("messy_invoice_renamed.csv"), invoice_spec())

      assert table.header_row == 10
      assert Enum.to_list(table.rows) == @rows
    end

    test "a decoy row is not taken for the header" do
      assert {:ok, table} = CSV.locate(layout("messy_invoice_decoy.csv"), invoice_spec())

      assert table.header_row == 10
    end

    test "the blank line ends a table even with a repeated header below it" do
      assert {:ok, table} = CSV.locate(layout("repeated_header.csv"), invoice_spec())

      assert Enum.to_list(table.rows) == Enum.take(@rows, 2)
    end

    test "the separator is detected when not given" do
      source = {:string, "Vendor;SKU;Item;Kg;Line Total\nABC123;78632478;apple;2;3\n"}

      assert {:ok, table} = CSV.locate(source, invoice_spec())
      assert [%{"sku" => "78632478", "total" => "3"}] = Enum.to_list(table.rows)
    end

    test "unknown options raise" do
      assert_raise ArgumentError, ~r/colour/, fn ->
        CSV.locate(layout("messy_invoice.csv"), invoice_spec(), colour: :blue)
      end
    end

    test "a malformed line in the header search is a parse error" do
      assert {:error, {:parse_error, message}} =
               CSV.locate({:string, "SKU,Line Total\n\"unclosed\n"}, invoice_spec())

      assert message =~ "escape character"
    end

    test "a malformed line under the header raises Refract.Errors.ParseError while streaming rows" do
      source = {:string, "Vendor,SKU,Item,Kg,Line Total\nABC123,78632478,apple,2,3\n\"bad\n"}

      assert {:ok, table} = CSV.locate(source, invoice_spec(), within: 2)
      assert_raise Refract.Errors.ParseError, fn -> Enum.to_list(table.rows) end
    end

    test "every spec column is on every row, nil when the file lacks it" do
      spec = invoice_spec(header: [columns: @columns, required: ["sku", "total"], min_matches: 3])

      assert {:ok, table} = CSV.locate({:string, "SKU,Item,Line Total\n1,apple,3\n"}, spec)

      assert table.header == ["sku", "item", "total", "cost_per_kg", "kg", "vendor"]
      assert table.columns == %{"sku" => 0, "item" => 1, "total" => 2}

      assert Enum.to_list(table.rows) == [
               %{
                 "sku" => "1",
                 "item" => "apple",
                 "total" => "3",
                 "cost_per_kg" => nil,
                 "kg" => nil,
                 "vendor" => nil
               }
             ]
    end

    test "open errors pass through" do
      assert {:error, :enoent} = CSV.locate(layout("missing.csv"), invoice_spec())
    end
  end

  describe "locate/3 misses" do
    test "a blank line inside a table is skipped, not a miss" do
      source = {:string, "SKU,Item,Kg,Line Total\n1,apple,2,3\n,,,\n2,pear,1,2\n"}

      assert {:ok, table} = CSV.locate(source, invoice_spec(stop: [], max_misses: 0))
      assert [%{"sku" => "1"}, %{"sku" => "2"}] = Enum.to_list(table.rows)
    end

    test "on_miss: :skip drops miss rows by default" do
      assert {:ok, table} = CSV.locate(layout("messy_invoice.csv"), invoice_spec())

      refute @subtotal in Enum.to_list(table.rows)
    end

    test "on_miss: :keep keeps miss rows" do
      assert {:ok, table} =
               CSV.locate(layout("messy_invoice.csv"), invoice_spec(), on_miss: :keep)

      assert Enum.to_list(table.rows) == [
               Enum.at(@rows, 0),
               Enum.at(@rows, 1),
               @subtotal,
               Enum.at(@rows, 2)
             ]
    end

    test "max_misses: 0 ends the table at the first miss" do
      assert {:ok, table} = CSV.locate(layout("messy_invoice.csv"), invoice_spec(max_misses: 0))

      assert Enum.to_list(table.rows) == Enum.take(@rows, 2)
    end

    test "raises on an unknown on_miss" do
      assert_raise ArgumentError, fn ->
        CSV.locate(layout("messy_invoice.csv"), invoice_spec(), on_miss: :ignore)
      end
    end

    test "checks locate options before opening the source" do
      assert_raise ArgumentError, fn ->
        CSV.locate(layout("missing.csv"), invoice_spec(), on_miss: :ignore)
      end

      assert_raise ArgumentError, fn ->
        CSV.locate(layout("missing.csv"), invoice_spec(), within: -1)
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
               CSV.locate(layout("no_table.csv"), invoice_spec())

      assert best.matched == []
      assert Enum.sort(best.missing) == ["sku", "total"]
    end

    test "only searches the first within: lines" do
      assert {:error, {:header_not_found, _}} =
               CSV.locate(layout("messy_invoice.csv"), invoice_spec(), within: 9)

      assert {:ok, _} = CSV.locate(layout("messy_invoice.csv"), invoice_spec(), within: 10)
    end
  end

  describe "locate/3 header_row:" do
    @two_tables {:string,
                 "SKU,Item,Kg,Line Total\nx,apple,2,y\n\nSKU,Item,Kg,Line Total\n1,apple,2,3\n"}

    test "takes the header at that line instead of searching" do
      assert {:ok, %Table{rows: rows}} = CSV.locate(@two_tables, invoice_spec())
      assert Enum.to_list(rows) == []

      assert {:ok, %Table{header_row: 4, rows: rows}} =
               CSV.locate(@two_tables, invoice_spec(), header_row: 4)

      assert [%{"sku" => "1", "total" => "3"}] = Enum.to_list(rows)
    end

    test "a line that is not the header is header_not_found naming that line" do
      assert {:error, {:header_not_found, %{row: 2, matched: [], missing: missing}}} =
               CSV.locate(@two_tables, invoice_spec(), header_row: 2)

      assert Enum.sort(missing) == ["sku", "total"]
    end

    test "a line past the end of the file is header_not_found" do
      assert {:error, {:header_not_found, nil}} =
               CSV.locate(@two_tables, invoice_spec(), header_row: 99)
    end

    test "can be past within:" do
      assert {:ok, %Table{header_row: 4}} =
               CSV.locate(@two_tables, invoice_spec(), header_row: 4, within: 1)
    end

    test "must be a positive integer" do
      for header_row <- [0, -1, "4"] do
        assert_raise ArgumentError, ~r/header_row/, fn ->
          CSV.locate(@two_tables, invoice_spec(), header_row: header_row)
        end
      end
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
