defmodule Refract.Grid.LookupTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  alias Refract.CSV
  alias Refract.Grid

  @invoice Path.expand("../../fixtures/layouts/messy_invoice.csv", __DIR__)

  defp invoice do
    {:ok, grid} = CSV.load(@invoice)
    grid
  end

  defp load!(source) do
    {:ok, grid} = CSV.load(source)
    grid
  end

  describe "load/2" do
    test "loads the whole source into a grid" do
      assert {:ok, grid} = CSV.load(@invoice)
      assert is_struct(grid, Grid)
    end

    test "loads string sources" do
      assert {:ok, grid} = CSV.load({:string, "id,name\n1,alice\n"})
      assert Grid.cell(grid, "B2") == "alice"
    end

    test "passes reader options through" do
      assert {:ok, grid} = CSV.load({:string, "id;name\n1;alice\n"}, separator: ";")
      assert Grid.cell(grid, "B2") == "alice"
    end

    test "open errors pass through" do
      assert {:error, :enoent} = CSV.load("missing.csv")
    end

    test "refuses a file over max_bytes" do
      assert {:error, {:max_bytes_exceeded, 100}} = CSV.load(@invoice, max_bytes: 100)
      assert {:ok, _grid} = CSV.load(@invoice, max_bytes: 1_000)
    end

    test "refuses a string over max_bytes" do
      assert {:error, {:max_bytes_exceeded, 5}} =
               CSV.load({:string, "id,name\n1,alice\n"}, max_bytes: 5)
    end
  end

  describe "cell/2" do
    test "reads a cell by its A1 ref" do
      grid = invoice()

      assert Grid.cell(grid, "A1") == "ACME Produce Pty Ltd"
      assert Grid.cell(grid, "B4") == "INV-0042"
      assert Grid.cell(grid, "H16") == "9.5"
    end

    test "a ref outside the grid is nil" do
      assert Grid.cell(invoice(), "Z99") == nil
    end

    test "a ref past the end of a short line is nil" do
      {:ok, grid} = CSV.load({:string, "a,b,c\nd\n"})

      assert Grid.cell(grid, "C2") == nil
    end

    test "reads two letter columns" do
      header = Enum.map_join(1..28, ",", &"c#{&1}")
      {:ok, grid} = CSV.load({:string, header <> "\n"})

      assert Grid.cell(grid, "Z1") == "c26"
      assert Grid.cell(grid, "AB1") == "c28"
    end

    test "raises on a bad ref" do
      grid = invoice()

      assert_raise ArgumentError, fn -> Grid.cell(grid, "B") end
      assert_raise ArgumentError, fn -> Grid.cell(grid, "1B") end
      assert_raise ArgumentError, fn -> Grid.cell(grid, "B0") end
    end
  end

  describe "range/2" do
    test "returns the raw cells of a range, row by row" do
      assert Grid.range(invoice(), "A4:B5") == [
               ["Invoice No", "INV-0042"],
               ["Date", "2010-01-01"]
             ]
    end

    test "a single cell range is one row of one cell" do
      assert Grid.range(invoice(), "B4:B4") == [["INV-0042"]]
    end

    test "cells outside the grid are nil" do
      assert Grid.range(invoice(), "H16:I17") == [["9.5", nil], [nil, nil]]
    end

    test "raises on a bad range" do
      assert_raise ArgumentError, fn -> Grid.range(invoice(), "A4") end
      assert_raise ArgumentError, fn -> Grid.range(invoice(), "B5:A4") end
    end
  end

  describe "table/2" do
    test "the first row of the range is the header, the rest are rows" do
      rows = invoice() |> Grid.table(at: "B10:H14") |> Enum.to_list()

      assert rows == [
               %{
                 "Vendor" => "ABC123",
                 "Line" => "1",
                 "SKU" => "78632478",
                 "Item" => "apple",
                 "Cost/kg" => "1.5",
                 "Kg" => "2",
                 "Line Total" => "3"
               },
               %{
                 "Vendor" => "DEF567",
                 "Line" => "2",
                 "SKU" => "12319082",
                 "Item" => "oarnge",
                 "Cost/kg" => "2.5",
                 "Kg" => "2",
                 "Line Total" => "5"
               },
               %{
                 "Vendor" => "",
                 "Line" => "",
                 "SKU" => "",
                 "Item" => "Subtotal",
                 "Cost/kg" => "",
                 "Kg" => "",
                 "Line Total" => "8"
               },
               %{
                 "Vendor" => "DEF567",
                 "Line" => "3",
                 "SKU" => "90834222",
                 "Item" => "pear",
                 "Cost/kg" => "0.5",
                 "Kg" => "3",
                 "Line Total" => "1.5"
               }
             ]
    end

    test "the header is normalised the same as CSV.stream" do
      {:ok, grid} = CSV.load({:string, " id ,,id\n1,2,3\n"})

      assert grid |> Grid.table(at: "A1:C2") |> Enum.to_list() == [
               %{"id" => "1", "col_1" => "2", "id_2" => "3"}
             ]
    end

    test "defaults to the whole grid" do
      {:ok, grid} = CSV.load({:string, "id,name\n1,alice\n2,bob\n"})

      assert grid |> Grid.table() |> Enum.to_list() == [
               %{"id" => "1", "name" => "alice"},
               %{"id" => "2", "name" => "bob"}
             ]
    end
  end

  describe "value/2" do
    test "takes the value right of a label" do
      assert Grid.value(invoice(), label: "Invoice No", take: :right) == "INV-0042"
    end

    test "take defaults to :right" do
      assert Grid.value(invoice(), label: "Invoice No") == "INV-0042"
    end

    test "ignores case and surrounding whitespace on a string label" do
      assert Grid.value(invoice(), label: "  invoice no ") == "INV-0042"
    end

    test "matches regex labels" do
      assert Grid.value(invoice(), label: ~r/^date$/i) == "2010-01-01"
      assert Grid.value(invoice(), label: ~r/invoice total/i) == "9.5"
    end

    test "a string label matches the whole cell" do
      grid = load!({:string, "Invoice Notes,x\nInvoice No,INV-1\n"})

      assert Grid.value(grid, label: "Invoice No") == "INV-1"
    end

    test "skips blank cells right of the label" do
      grid = load!({:string, "Total,, ,42\n"})

      assert Grid.value(grid, label: "Total") == "42"
    end

    test "takes the value below a label" do
      grid = load!({:string, "Name,Age\n,\nAlice,30\n"})

      assert Grid.value(grid, label: "Age", take: :below) == "30"
    end

    test "the first label in reading order wins" do
      grid = load!({:string, "x,Total,1\nTotal,2\n"})

      assert Grid.value(grid, label: "Total") == "1"
    end

    test "nil when the label is not found" do
      assert Grid.value(invoice(), label: "PO Number") == nil
    end

    test "nil when nothing follows the label" do
      grid = load!({:string, "Total,,\nNotes\n"})

      assert Grid.value(grid, label: "Total") == nil
      assert Grid.value(grid, label: "Notes", take: :below) == nil
    end

    test "skips cells that are not strings and returns native values" do
      grid = Grid.new([[nil, 7, "Total", nil, 42]])

      assert Grid.value(grid, label: "Total") == 42
    end

    test "raises without a label" do
      assert_raise ArgumentError, fn -> Grid.value(invoice(), take: :right) end
    end

    test "raises on an unknown take" do
      assert_raise ArgumentError, fn -> Grid.value(invoice(), label: "Total", take: :left) end
    end
  end

  describe "block/2" do
    test "takes the lines below a label until a blank" do
      assert Grid.block(invoice(), after: "Bill To", until: :blank) == [
               "Lean Davis",
               "4 Farm Rd, Orange"
             ]
    end

    test "until defaults to :blank" do
      assert Grid.block(invoice(), after: "Bill To") == ["Lean Davis", "4 Farm Rd, Orange"]
    end

    test "matches regex labels" do
      assert Grid.block(invoice(), after: ~r/^bill to$/i) == ["Lean Davis", "4 Farm Rd, Orange"]
    end

    test "reads down the label column" do
      grid = load!({:string, "x,Address\ny,1 Main St\nz,Orange\n"})

      assert Grid.block(grid, after: "Address") == ["1 Main St", "Orange"]
    end

    test "runs to the end of the grid" do
      grid = load!({:string, "Notes\na\nb\n"})

      assert Grid.block(grid, after: "Notes") == ["a", "b"]
    end

    test "a whitespace cell, nil or a short row ends the block" do
      assert Grid.block(Grid.new([["Notes"], ["a"], ["  "], ["b"]]), after: "Notes") == ["a"]
      assert Grid.block(Grid.new([["Notes"], ["a"], [nil], ["b"]]), after: "Notes") == ["a"]

      assert Grid.block(Grid.new([["x", "Notes"], ["y", "a"], ["z"], ["w", "b"]]), after: "Notes") ==
               ["a"]
    end

    test "empty when a blank follows the label" do
      grid = load!({:string, "Notes\n\na\n"})

      assert Grid.block(grid, after: "Notes") == []
    end

    test "nil when the label is not found" do
      assert Grid.block(invoice(), after: "Ship To") == nil
    end

    test "raises without after" do
      assert_raise ArgumentError, fn -> Grid.block(invoice(), until: :blank) end
    end

    test "raises on an unknown until" do
      assert_raise ArgumentError, fn -> Grid.block(invoice(), after: "Bill To", until: :eof) end
    end
  end
end
