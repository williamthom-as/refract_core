defmodule Refract.DocumentRulesTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag timeout: 10_000

  alias Refract.CSV
  alias Refract.Grid
  alias Refract.Parse
  alias Refract.Shape
  alias Refract.Table
  alias Refract.Validate

  defp form(total, line_total \\ "99.00") do
    """
    ACME PTY LTD - Tax Invoice,,
    Invoice No,INV-1001,
    ,,
    SKU,Qty,Line Total
    A-100,3,37.50
    B-200,1,#{line_total}
    ,,
    Total,,#{total}
    """
  end

  defp spec do
    Table.spec(
      header: [columns: %{"sku" => ["sku"], "qty" => ["qty"], "line_total" => ["line total"]}],
      stop: [:blank]
    )
  end

  defp invoice(document, opts \\ []) do
    Shape.new(
      name: "acme_invoice",
      spec: spec(),
      validation: [
        columns: Keyword.get(opts, :columns, %{"line_total" => [:required, :number]}),
        document: document
      ],
      fields: Keyword.get(opts, :fields, %{"total" => [label: "total", rules: [:required]]})
    )
  end

  defp total_matches_lines?(%{fields: %{"total" => total}, rows: rows}) do
    rows
    |> Enum.map(&Parse.number!(&1["line_total"]))
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
    |> Decimal.eq?(Parse.number!(total))
  end

  defp totalled, do: invoice([{:total_matches_lines, &total_matches_lines?/1}])

  describe "Shape.new/1 document rules" do
    test "a shape keeps its document rules" do
      assert [{:total_matches_lines, fun}] = totalled().validation.document
      assert is_function(fun, 1)
    end

    test "document rules are optional" do
      assert Shape.new(name: "plain", spec: spec()).validation.document == []
    end

    test "a document rule must be a named one argument function" do
      for rule <- [:total, {:total, "fn"}, {"total", &is_map/1}, {:total, &Map.get/2}] do
        assert_raise ArgumentError, ~r/document rule/, fn -> invoice([rule]) end
      end
    end

    test "document rules are elixir only" do
      map = %{
        "name" => "acme_invoice",
        "header" => %{"columns" => %{"sku" => ["sku"]}},
        "validation" => %{"document" => ["total_matches_lines"]}
      }

      assert {:error, {:unknown_key, "validation.document"}} = Shape.from_map(map)
    end
  end

  describe "validating a document" do
    test "a document whose rules hold is valid" do
      assert {:ok, %{valid: true, rows: 2, issues: []}} =
               CSV.validate({:string, form("136.50")}, totalled())
    end

    test "a failing document rule is an issue by name, with no line" do
      assert {:ok, %{valid: false, issues: [issue]}} =
               CSV.validate({:string, form("150.00")}, totalled())

      assert %{rule: :total_matches_lines, line: nil, column: nil, field: nil} = issue
    end

    test "a rule gets the field values and every table row" do
      test = self()
      shape = invoice([{:seen, &send(test, {:document, &1})}])

      assert {:ok, _result} = CSV.validate({:string, form("136.50")}, shape)

      assert_received {:document,
                       %{
                         fields: %{"total" => "136.50"},
                         rows: [
                           %{"sku" => "A-100", "qty" => "3", "line_total" => "37.50"},
                           %{"sku" => "B-200", "qty" => "1", "line_total" => "99.00"}
                         ]
                       }}
    end

    test "a rule that raises fails" do
      shape = invoice([{:explodes, fn _document -> raise "rule bug" end}])

      assert {:ok, %{valid: false, issues: [%{rule: :explodes, line: nil}]}} =
               CSV.validate({:string, form("136.50")}, shape)
    end

    test "document rules run after cells have failed, their issues come last" do
      assert {:ok, %{issues: issues}} =
               CSV.validate({:string, form("136.50", "n/a")}, totalled())

      assert [%{line: 6, column: "line_total", rule: :number}, %{rule: :total_matches_lines}] =
               issues
    end

    test "every failing document rule is reported, in the order written" do
      shape = invoice([{:second, fn _document -> false end}, {:first, fn _document -> false end}])

      assert {:ok, %{issues: [%{rule: :second}, %{rule: :first}]}} =
               CSV.validate({:string, form("136.50")}, shape)
    end

    test "field issues, table issues, then document issues" do
      shape =
        invoice([{:total_matches_lines, &total_matches_lines?/1}],
          fields: %{
            "invoice_no" => [label: "invoice no", rules: [~r/^PO-/]],
            "total" => [label: "total", rules: [:required]]
          }
        )

      assert {:ok, %{issues: issues}} =
               CSV.validate({:string, form("150.00", "n/a")}, shape)

      assert [
               %{field: "invoice_no"},
               %{column: "line_total", rule: :number},
               %{rule: :total_matches_lines}
             ] = issues
    end

    test "a shape with document rules and no fields gets empty fields" do
      test = self()
      shape = invoice([{:seen, &send(test, {:document, &1})}], fields: %{})

      assert {:ok, %{valid: true, rows: 2}} = CSV.validate({:string, form("136.50")}, shape)
      assert_received {:document, %{fields: fields, rows: [_first, _second]}}
      assert fields == %{}
    end

    test "a shape with document rules is validated in memory, max_bytes guards it", %{
      tmp_dir: dir
    } do
      path = Path.join(dir, "invoice.csv")
      File.write!(path, form("136.50"))
      shape = invoice([{:any_rows, &(&1.rows != [])}], fields: %{})

      assert {:error, {:max_bytes_exceeded, 10}} = CSV.validate(path, shape, max_bytes: 10)
      assert {:ok, %{valid: true}} = CSV.validate(path, shape)
    end

    test "no table, no document rules run" do
      test = self()
      shape = invoice([{:seen, &send(test, {:document, &1})}])

      assert {:error, {:header_not_found, _miss}} =
               CSV.validate({:string, "nothing,here\n1,2\n"}, shape)

      refute_received {:document, _document}
    end

    test "a loaded grid runs document rules too" do
      {:ok, grid} = CSV.load({:string, form("150.00")})

      assert {:ok, %{valid: false, issues: [%{rule: :total_matches_lines}]}} =
               Grid.validate(grid, totalled())
    end

    test "Validate.rows tags rows only, document rules need the whole document" do
      rows = [%{"sku" => "A-100", "qty" => "3", "line_total" => "37.50"}]
      shape = invoice([{:never, fn _document -> false end}])

      assert [{:ok, _row}] = rows |> Validate.rows(shape) |> Enum.to_list()
    end
  end
end
