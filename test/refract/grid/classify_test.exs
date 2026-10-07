defmodule Refract.Grid.ClassifyTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  alias Refract.CSV
  alias Refract.Grid
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

  @positions %{
    "vendor" => 1,
    "sku" => 3,
    "item" => 4,
    "cost_per_kg" => 5,
    "kg" => 6,
    "total" => 7
  }

  defp layout(name), do: Path.join(@layouts, name)

  defp load!(source) do
    {:ok, grid} = CSV.load(source)

    grid
  end

  defp invoice_spec do
    Table.spec(
      header: [columns: @columns, required: ["sku", "total"], min_matches: 4],
      row: [match: %{"sku" => :integer, "total" => :number}],
      stop: [:blank, {:contains, ~r/invoice total/i}],
      max_misses: 1
    )
  end

  defp small_spec do
    Table.spec(
      header: [columns: %{"sku" => ["sku"], "total" => ["total"]}],
      row: [match: %{"sku" => :integer}]
    )
  end

  defp classes(lines), do: Enum.map(lines, &{elem(&1, 0), elem(&1, 1)})

  describe "classify/2" do
    test "gives every line a class in order" do
      lines = Grid.classify(load!(layout("messy_invoice.csv")), invoice_spec())

      assert classes(lines) ==
               Enum.map(1..9, &{:other, &1}) ++
                 [
                   {:header, 10},
                   {:row, 11},
                   {:row, 12},
                   {:other, 13},
                   {:row, 14},
                   {:other, 15},
                   {:other, 16}
                 ]
    end

    test "a header carries its column positions" do
      lines = Grid.classify(load!(layout("messy_invoice.csv")), invoice_spec())

      assert {:header, 10, @positions} in lines
    end

    test "a row carries its canonical map" do
      lines = Grid.classify(load!(layout("messy_invoice.csv")), invoice_spec())

      row = %{
        "vendor" => "ABC123",
        "sku" => "78632478",
        "item" => "apple",
        "cost_per_kg" => "1.5",
        "kg" => "2",
        "total" => "3"
      }

      assert {:row, 11, row} in lines
    end

    test "other carries the raw cells" do
      lines = Grid.classify(load!(layout("messy_invoice.csv")), invoice_spec())

      assert {:other, 13, ["", "", "", "", "Subtotal", "", "", "8"]} in lines
    end

    test "stop conditions do not end classification" do
      lines = Grid.classify(load!(layout("repeated_header.csv")), invoice_spec())

      assert classes(lines) |> Enum.filter(&match?({:header, _}, &1)) == [
               {:header, 10},
               {:header, 15}
             ]

      assert classes(lines) |> Enum.filter(&match?({:row, _}, &1)) == [
               {:row, 11},
               {:row, 12},
               {:row, 16}
             ]
    end

    test "a line before any header is other" do
      grid = load!({:string, "1,2\nsku,total\n3,4\n"})

      assert Grid.classify(grid, small_spec()) == [
               {:other, 1, ["1", "2"]},
               {:header, 2, %{"sku" => 0, "total" => 1}},
               {:row, 3, %{"sku" => "3", "total" => "4"}}
             ]
    end

    test "rows follow the latest header" do
      grid = load!({:string, "sku,total\n1,2\ntotal,sku\n3,4\n"})

      assert {:row, 4, %{"sku" => "4", "total" => "3"}} in Grid.classify(grid, small_spec())
    end

    test "rows match locate on the messy invoice" do
      grid = load!(layout("messy_invoice.csv"))

      {:ok, table} = Grid.locate(grid, invoice_spec())

      rows = for {:row, _line, row} <- Grid.classify(grid, invoice_spec()), do: row

      assert rows == Enum.to_list(table.rows)
    end

    test "an empty grid has no lines" do
      assert Grid.classify(Grid.new([]), invoice_spec()) == []
    end
  end

  describe "explain/2" do
    test "gives every line a class and why" do
      grid = load!({:string, "1,2\nsku,total\n3,4\nx,5\n"})

      assert Grid.explain(grid, small_spec()) == [
               %{line: 1, class: :other, why: {:header_miss, %{matched: [], missing: []}}},
               %{line: 2, class: :header, why: :header_matched},
               %{line: 3, class: :row, why: :row_matched},
               %{
                 line: 4,
                 class: :other,
                 why: {:row_miss, %{score: 0.0, failed: [{"sku", :integer}]}}
               }
             ]
    end

    test "a header miss says what the line lacked" do
      lines = Grid.explain(load!(layout("messy_invoice.csv")), invoice_spec())

      assert %{line: 1, class: :other, why: {:header_miss, miss}} = hd(lines)
      assert miss.matched == []
      assert Enum.sort(miss.missing) == ["sku", "total"]
    end

    test "a row miss says which rules failed" do
      lines = Grid.explain(load!(layout("messy_invoice.csv")), invoice_spec())

      assert %{line: 13, class: :other, why: {:row_miss, %{score: 0.5, failed: failed}}} =
               Enum.at(lines, 12)

      assert failed == [{"sku", :integer}]
    end

    test "classes agree with classify" do
      grid = load!(layout("repeated_header.csv"))

      explained =
        for %{line: line, class: class} <- Grid.explain(grid, invoice_spec()), do: {class, line}

      assert explained == classes(Grid.classify(grid, invoice_spec()))
    end

    test "an empty grid has no lines" do
      assert Grid.explain(Grid.new([]), invoice_spec()) == []
    end
  end
end
