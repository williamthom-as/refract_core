defmodule Refract.FieldsTest.Invoice do
  use Refract.Shape

  @impl Refract.Shape
  def shape, do: Refract.FieldsTest.invoice()
end

defmodule Refract.FieldsTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag timeout: 10_000

  alias Refract.CSV
  alias Refract.FieldsTest.Invoice
  alias Refract.Grid
  alias Refract.Shape
  alias Refract.Table

  @form """
  Tax Invoice,,
  Invoice No,INV-1002,
  Invoice Date,,
  2026-10-05,,
  Supplier,Acme Pty Ltd,
  ,,
  SKU,Qty,Line Total
  A-100,2,25.00
  ,,
  Total Due,,25.00
  """

  defp spec,
    do: Table.spec(header: [columns: %{"sku" => ["sku"], "line_total" => ["line total"]}])

  def invoice(fields \\ default_fields()),
    do: Shape.new(name: "invoice", spec: spec(), fields: fields)

  defp default_fields do
    %{
      "invoice_no" => [label: "invoice no", rules: [:required, ~r/^INV-\d+$/]],
      "issued_on" => [label: "invoice date", take: :below, rules: [:required, :date]],
      "supplier" => [at: "B5"],
      "total_due" => [label: ~r/^total due$/i, rules: [:required, :number]]
    }
  end

  defp grid!(csv \\ @form) do
    {:ok, grid} = CSV.load({:string, csv})

    grid
  end

  describe "Shape.new/1 fields:" do
    test "a shape keeps its fields, how to find each and its rules" do
      fields = invoice().fields

      assert %{label: "invoice no", take: :right, at: nil, rules: [:required, _regex]} =
               fields["invoice_no"]

      assert %{label: "invoice date", take: :below} = fields["issued_on"]
      assert %{label: nil, at: "B5", rules: []} = fields["supplier"]
      assert %{label: %Regex{}} = fields["total_due"]
    end

    test "fields are optional" do
      assert Shape.new(name: "plain", spec: spec()).fields == %{}
    end

    test "a field is found by a label or a cell, not both, not neither" do
      for field <- [[rules: [:required]], [label: "invoice no", at: "B2"]] do
        assert_raise ArgumentError, ~r/field/, fn -> invoice(%{"invoice_no" => field}) end
      end
    end

    test "bad field options raise" do
      for field <- [
            [label: "invoice no", take: :left],
            [label: :invoice_no],
            [at: "not a cell"],
            [label: "invoice no", rules: [:shiny]],
            [label: "invoice no", colour: :blue]
          ] do
        assert_raise ArgumentError, fn -> invoice(%{"invoice_no" => field}) end
      end
    end
  end

  describe "Grid.fields/2" do
    test "reads every field by its label or cell" do
      assert Grid.fields(grid!(), invoice()) == %{
               "invoice_no" => "INV-1002",
               "issued_on" => "2026-10-05",
               "supplier" => "Acme Pty Ltd",
               "total_due" => "25.00"
             }
    end

    test "a label that is not there gives nil" do
      shape = invoice(%{"po_number" => [label: "purchase order"]})

      assert Grid.fields(grid!(), shape) == %{"po_number" => nil}
    end

    test "native cells come back as they are" do
      grid = Grid.new([["Invoice No", "INV-7"], ["Total Due", Decimal.new("25.00")]])

      assert %{"total_due" => total} = Grid.fields(grid, invoice())
      assert total == Decimal.new("25.00")
    end

    test "a shape without fields reads nothing" do
      assert Grid.fields(grid!(), Shape.new(name: "plain", spec: spec())) == %{}
    end

    test "the shape can be a module" do
      assert %{"invoice_no" => "INV-1002"} = Grid.fields(grid!(), Invoice)
    end
  end

  describe "reader fields/3" do
    test "loads the file and reads its fields" do
      assert {:ok, %{"invoice_no" => "INV-1002", "total_due" => "25.00"}} =
               CSV.fields({:string, @form}, invoice())
    end

    test "a source that cannot be read is an error" do
      assert {:error, :enoent} = CSV.fields("missing.csv", invoice())
    end

    test "a file over max_bytes is an error, as load", %{tmp_dir: dir} do
      path = Path.join(dir, "form.csv")
      File.write!(path, @form)

      assert {:error, {:max_bytes_exceeded, 10}} = CSV.fields(path, invoice(), max_bytes: 10)
    end
  end

  describe "Shape.from_map/1 fields" do
    test "fields come from the map" do
      map = %{
        "name" => "invoice",
        "header" => %{"columns" => %{"sku" => ["sku"]}},
        "fields" => %{
          "invoice_no" => %{"label" => "invoice no", "rules" => ["required", "/^INV-\\d+$/"]},
          "issued_on" => %{"label" => "invoice date", "take" => "below", "rules" => ["date"]},
          "supplier" => %{"at" => "B5"}
        }
      }

      assert {:ok, shape} = Shape.from_map(map)

      assert %{label: "invoice no", take: :right, rules: [:required, %Regex{}]} =
               shape.fields["invoice_no"]

      assert %{take: :below, rules: [:date]} = shape.fields["issued_on"]
      assert %{at: "B5"} = shape.fields["supplier"]
    end

    test "a bad field in the map is an error naming where" do
      map = %{
        "name" => "invoice",
        "header" => %{"columns" => %{"sku" => ["sku"]}},
        "fields" => %{"invoice_no" => %{"label" => "invoice no", "rules" => ["shiny"]}}
      }

      assert {:error, {:invalid_value, {"fields.invoice_no.rules", "shiny"}}} =
               Shape.from_map(map)
    end
  end

  describe "validating fields" do
    defp checked(fields \\ default_fields()) do
      Shape.new(
        name: "invoice",
        spec:
          Table.spec(
            header: [
              columns: %{"sku" => ["sku"], "qty" => ["qty"], "line_total" => ["line total"]}
            ],
            stop: [:blank]
          ),
        validation: [columns: %{"line_total" => [{:max, 10_000}]}],
        fields: fields
      )
    end

    defp form(invoice_no, line_total) do
      """
      Tax Invoice,,
      Invoice No,#{invoice_no},
      Invoice Date,,
      2026-10-05,,
      Supplier,Acme Pty Ltd,
      ,,
      SKU,Qty,Line Total
      A-100,2,#{line_total}
      ,,
      Total Due,,#{line_total}
      """
    end

    test "a field breaking its rule is an issue at its label's line" do
      assert {:ok, result} = Grid.validate(grid!(form("XYZ", "25.00")), checked())

      refute result.valid
      assert [%{line: 2, field: "invoice_no", column: nil, rule: %Regex{}}] = result.issues
    end

    test "the values read are on the result" do
      assert {:ok, result} = Grid.validate(grid!(form("INV-1002", "25.00")), checked())

      assert result.valid
      assert result.fields["invoice_no"] == "INV-1002"
      assert result.fields["issued_on"] == "2026-10-05"
    end

    test "a missing label fails :required with no line, and passes without it" do
      required = checked(%{"po_number" => [label: "purchase order", rules: [:required]]})
      optional = checked(%{"po_number" => [label: "purchase order", rules: [~r/^PO/]]})
      grid = grid!(form("INV-1002", "25.00"))

      assert {:ok, %{issues: [%{field: "po_number", rule: :required, line: nil}]}} =
               Grid.validate(grid, required)

      assert {:ok, %{valid: true}} = Grid.validate(grid, optional)
    end

    test "a field found by cell reports that cell's line" do
      shape = checked(%{"supplier" => [at: "B5", rules: [~r/^Globex/]]})

      assert {:ok, %{issues: [%{field: "supplier", line: 5}]}} =
               Grid.validate(grid!(form("INV-1002", "25.00")), shape)
    end

    test "field issues come before table issues" do
      assert {:ok, result} = Grid.validate(grid!(form("XYZ", "12500.00")), checked())

      assert [%{field: "invoice_no"}, %{column: "line_total", field: nil}] = result.issues
    end

    test "values: true puts the field's cell in its issue" do
      assert {:ok, %{issues: [%{field: "invoice_no", value: "XYZ"}]}} =
               Grid.validate(grid!(form("XYZ", "25.00")), checked(), values: true)
    end

    test "a reader validates the fields of a shape that has them" do
      assert {:ok, result} = CSV.validate({:string, form("XYZ", "25.00")}, checked())

      assert [%{field: "invoice_no", line: 2}] = result.issues
      assert result.fields["supplier"] == "Acme Pty Ltd"
    end

    test "a reader keeps max_bytes for a shape with fields", %{tmp_dir: dir} do
      path = Path.join(dir, "form.csv")
      File.write!(path, form("INV-1002", "25.00"))

      assert {:error, {:max_bytes_exceeded, 10}} = CSV.validate(path, checked(), max_bytes: 10)
    end

    test "a shape without fields still streams" do
      shape = checked(%{})
      chunks = [form("XYZ", "25.00")]

      assert {:ok, %{valid: true, fields: fields}} = CSV.validate({:stream, chunks}, shape)
      assert fields == %{}
    end
  end
end
