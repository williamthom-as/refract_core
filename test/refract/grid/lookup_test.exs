defmodule Refract.Grid.LookupTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  alias Refract.CSV
  alias Refract.Grid

  @invoice Path.expand("../../fixtures/shapes/messy_invoice.csv", __DIR__)

  defp invoice do
    {:ok, grid} = CSV.load(@invoice)
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
      assert Grid.cell(grid, "H16") == "17.5"
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
      assert Grid.range(invoice(), "H16:I17") == [["17.5", nil], [nil, nil]]
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
end
