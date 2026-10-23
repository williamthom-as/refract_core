defmodule Refract.Grid.ValidateTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 10_000

  alias Refract.CSV
  alias Refract.Grid
  alias Refract.Shape
  alias Refract.Table

  defp invoice do
    Shape.new(
      name: "invoice",
      spec:
        Table.spec(
          header: [columns: %{"sku" => ["sku"], "qty" => ["qty"], "line_total" => ["line total"]}],
          row: [match: %{"line_total" => :number}],
          stop: [:blank]
        ),
      validation: [
        columns: %{
          "sku" => [:required],
          "qty" => [:integer],
          "line_total" => [:required, {:max, 10_000}]
        }
      ]
    )
  end

  @form """
  Tax Invoice,,
  Invoice No,INV-42,
  ,,
  Bill To,,
  Acme Pty Ltd,,
  ,,
  SKU,Qty,Line Total
  A-100,2,25.00
  C-300,1,12500.00
  D-400,x,n/a
  B-200,4,396.00
  """

  defp load!(source) do
    {:ok, grid} = CSV.load(source)

    grid
  end

  describe "validate/3" do
    test "issues name the line in the grid" do
      assert {:ok, result} = Grid.validate(load!({:string, @form}), invoice())

      refute result.valid
      assert result.rows == 4

      assert [
               %{line: 9, column: "line_total", rule: {:max, 10_000}},
               %{line: 10, column: "line_total", rule: {:max, 10_000}},
               %{line: 10, column: "qty", rule: :integer}
             ] = result.issues
    end

    test "gives the same result as validating the same lines from the file" do
      assert Grid.validate(load!({:string, @form}), invoice()) ==
               CSV.validate({:string, @form}, invoice())
    end

    test "searches the whole grid by default" do
      csv = String.duplicate("junk\n", 149) <> "sku,qty,line total\nA-100,2,25.00\n"

      assert {:error, {:header_not_found, _miss}} = CSV.validate({:string, csv}, invoice())
      assert {:ok, %{valid: true, rows: 1}} = Grid.validate(load!({:string, csv}), invoice())
    end

    test "a grid without the shape's header is an error" do
      assert {:error, {:header_not_found, _miss}} =
               Grid.validate(load!({:string, "name,colour\nfig,purple\n"}), invoice())
    end

    test "options pass through" do
      grid = load!({:string, @form})

      assert {:ok, %{issues: [%{value: "12500.00"} | _rest]}} =
               Grid.validate(grid, invoice(), values: true)

      assert {:error, {:header_not_found, _miss}} = Grid.validate(grid, invoice(), header_row: 2)
    end
  end
end
