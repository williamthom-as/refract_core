defmodule Refract.E2E.InvoiceTest do
  use ExUnit.Case, async: true

  @moduletag :e2e
  @moduletag timeout: 5_000

  alias Refract.CSV
  alias Refract.Golden
  alias Refract.Grid
  alias Refract.Table

  @golden Golden.path("invoice", "input.csv")
  @messy Path.expand("../../fixtures/shapes/messy_invoice.csv", __DIR__)

  @golden_rows [
    %{
      "vendor" => "ABC123",
      "line_item" => "1",
      "sku" => "78632478",
      "item" => "apple",
      "cost_per_kilo" => "1.5",
      "amount_in_kilo" => "2",
      "total_cost" => "3"
    },
    %{
      "vendor" => "DEF567",
      "line_item" => "2",
      "sku" => "12319082",
      "item" => "oarnge",
      "cost_per_kilo" => "2.5",
      "amount_in_kilo" => "2",
      "total_cost" => "5"
    },
    %{
      "vendor" => "DEF567",
      "line_item" => "3",
      "sku" => "90834222",
      "item" => "pear",
      "cost_per_kilo" => "0.5",
      "amount_in_kilo" => "3",
      "total_cost" => "1.5"
    },
    %{
      "vendor" => "ABC123",
      "line_item" => "4",
      "sku" => "78632478",
      "item" => "apple",
      "cost_per_kilo" => "1.5",
      "amount_in_kilo" => "1",
      "total_cost" => "1.5"
    },
    %{
      "vendor" => "ABC123",
      "line_item" => "5",
      "sku" => "78632478",
      "item" => "apple",
      "cost_per_kilo" => "1.5",
      "amount_in_kilo" => "1",
      "total_cost" => "1.5"
    },
    %{
      "vendor" => "DEF567",
      "line_item" => "6",
      "sku" => "12319082",
      "item" => "oarnge",
      "cost_per_kilo" => "2.5",
      "amount_in_kilo" => "2",
      "total_cost" => "5"
    }
  ]

  defp load!(path) do
    {:ok, grid} = CSV.load(path)

    grid
  end

  defp golden_spec do
    columns =
      Map.new(
        ~w(vendor line_item sku item cost_per_kilo amount_in_kilo total_cost),
        &{&1, [&1]}
      )

    Table.spec(
      header: [columns: columns, required: ["sku", "total_cost"]],
      row: [match: %{"sku" => :integer, "total_cost" => :number}],
      stop: [:blank]
    )
  end

  defp messy_spec do
    Table.spec(
      header: [
        columns: %{
          "vendor" => ["vendor"],
          "sku" => ["sku"],
          "item" => ["item"],
          "cost_per_kg" => ["cost/kg"],
          "kg" => ["kg"],
          "total" => ["line total"]
        },
        required: ["sku", "total"],
        min_matches: 4
      ],
      row: [match: %{"sku" => :integer, "total" => :number}],
      stop: [:blank, {:contains, ~r/invoice total/i}],
      max_misses: 1
    )
  end

  defp sum(rows, column) do
    rows
    |> Enum.map(fn row -> row |> Map.fetch!(column) |> Float.parse() |> elem(0) end)
    |> Enum.sum()
  end

  describe "cure invoice by fixed refs" do
    test "values above and below the table" do
      grid = load!(@golden)

      assert Grid.cell(grid, "B1") == "2010-01-01"
      assert Grid.cell(grid, "G12") == "17.5"
    end

    test "the table at A4:G10" do
      assert load!(@golden) |> Grid.table(at: "A4:G10") |> Enum.to_list() == @golden_rows
    end

    test "rows add up to the invoice total" do
      grid = load!(@golden)
      rows = Grid.table(grid, at: "A4:G10")

      assert sum(rows, "total_cost") == grid |> Grid.cell("G12") |> String.to_float()
    end
  end

  describe "cure invoice by pattern" do
    test "locate finds the same rows as the fixed refs" do
      grid = load!(@golden)

      assert {:ok, table} = Grid.locate(grid, golden_spec())

      assert table.header_row == 4
      assert Enum.to_list(table.rows) == @golden_rows
    end

    test "labels find the same values as the fixed refs" do
      grid = load!(@golden)

      assert Grid.value(grid, label: "Date") == Grid.cell(grid, "B1")
      assert Grid.value(grid, label: ~r/invoice total/i) == Grid.cell(grid, "G12")
      assert Grid.value(grid, label: "Purchaser") == "Lean Davis"
    end
  end

  describe "messy invoice by pattern" do
    test "extracts the table and every value around it" do
      grid = load!(@messy)

      assert {:ok, table} = Grid.locate(grid, messy_spec())

      assert table.header_row == 10
      assert table.header == ["vendor", "sku", "item", "cost_per_kg", "kg", "total"]

      assert table.rows |> Enum.to_list() |> Enum.map(& &1["sku"]) == [
               "78632478",
               "12319082",
               "90834222"
             ]

      assert Grid.value(grid, label: "Invoice No") == "INV-0042"
      assert Grid.value(grid, label: ~r/^date$/i) == "2010-01-01"
      assert Grid.block(grid, after: "Bill To") == ["Lean Davis", "4 Farm Rd, Orange"]
      assert Grid.value(grid, label: ~r/invoice total/i) == "9.5"
    end

    test "rows add up to the invoice total" do
      grid = load!(@messy)

      {:ok, table} = Grid.locate(grid, messy_spec())

      assert sum(table.rows, "total") ==
               grid |> Grid.value(label: ~r/invoice total/i) |> String.to_float()
    end

    test "the subtotal is not a row" do
      {:ok, table} = Grid.locate(load!(@messy), messy_spec())

      refute Enum.any?(table.rows, &(&1["item"] == "Subtotal"))
    end
  end
end
