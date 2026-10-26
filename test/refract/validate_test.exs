defmodule Refract.ValidateTest.Invoice do
  use Refract.Shape

  @impl Refract.Shape
  def shape, do: Refract.ValidateTest.invoice()
end

defmodule Refract.ValidateTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 10_000

  alias Refract.CSV
  alias Refract.Shape
  alias Refract.Table
  alias Refract.Validate
  alias Refract.ValidateTest.Invoice

  @columns %{
    "sku" => ["sku"],
    "description" => ["description"],
    "qty" => ["qty"],
    "unit_price" => ["unit price"],
    "line_total" => ["line total"]
  }

  defp spec, do: Table.spec(header: [columns: @columns], row: [match: %{"qty" => :number}])

  def invoice(validation \\ default_validation()),
    do: Shape.new(name: "invoice", spec: spec(), validation: validation)

  defp default_validation do
    [
      columns: %{
        "sku" => [:required, ~r/^[A-Z]-\d{3}$/],
        "qty" => [:required, :integer, {:min, 1}],
        "unit_price" => [:number, {:min, 0}],
        "line_total" => [:required, :number, {:max, 10_000}]
      },
      rows: [{:line_total_adds_up, &adds_up?/1}]
    ]
  end

  defp adds_up?(row) do
    {:ok, qty} = Refract.Parse.number(row["qty"])
    {:ok, price} = Refract.Parse.number(row["unit_price"])
    {:ok, total} = Refract.Parse.number(row["line_total"])

    Decimal.eq?(Decimal.mult(qty, price), total)
  end

  defp line(overrides) do
    Map.merge(
      %{
        "sku" => "A-100",
        "description" => "widget",
        "qty" => "2",
        "unit_price" => "12.50",
        "line_total" => "25.00"
      },
      overrides
    )
  end

  defp validate(rows, shape \\ invoice(), opts \\ []),
    do: rows |> Validate.rows(shape, opts) |> Enum.to_list()

  defp issues([{:invalid, _row, issues}]), do: issues
  defp issues([{:ok, _row}]), do: []

  describe "rows/3" do
    test "a row passing every rule is ok" do
      row = line(%{})

      assert validate([row]) == [{:ok, row}]
    end

    test "a failing column rule names the row, the column and the rule" do
      row = line(%{"line_total" => "12500.00", "unit_price" => "6250.00"})

      assert [{:ok, _first}, {:invalid, ^row, [issue]}] = validate([line(%{}), row])
      assert %{line: 2, column: "line_total", rule: {:max, 10_000}} = issue
    end

    test "each row is tagged on its own" do
      rows = [line(%{}), line(%{"sku" => "bad"}), line(%{"sku" => "B-200"})]

      assert [{:ok, _}, {:invalid, _, [%{line: 2, column: "sku"}]}, {:ok, _}] = validate(rows)
    end

    test "a column reports only its first failing rule" do
      assert [%{column: "line_total", rule: :number}] =
               issues(validate([line(%{"line_total" => "n/a"})]))
               |> Enum.reject(&(&1.column == nil))
    end

    test "every failing column is reported, in column order" do
      issues = issues(validate([line(%{"sku" => "", "qty" => "0"})]))

      assert [%{column: "qty", rule: {:min, 1}}, %{column: "sku", rule: :required}] =
               Enum.reject(issues, &(&1.column == nil))
    end

    test "a blank cell fails only :required, other rules skip it" do
      row = line(%{"unit_price" => "", "line_total" => ""})

      assert [{:invalid, ^row, [issue]}] =
               validate([row], invoice(columns: default_validation()[:columns]))

      assert %{line: 1, column: "line_total", rule: :required, value: nil} = issue
    end

    test "a nil cell is blank, it fails :required and other rules skip it" do
      row = line(%{"unit_price" => nil, "line_total" => nil})

      assert [{:invalid, ^row, [issue]}] =
               validate([row], invoice(columns: default_validation()[:columns]))

      assert %{line: 1, column: "line_total", rule: :required, value: nil} = issue
    end

    test "a false cell is checked like any other" do
      pattern = ~r/^[A-Z]-\d{3}$/
      shape = invoice(columns: %{"sku" => [:required, pattern]})

      assert [%{column: "sku", rule: ^pattern}] =
               issues(validate([line(%{"sku" => false})], shape))
    end

    test "min and max compare numbers, whatever their form" do
      shape = invoice(columns: %{"line_total" => [{:min, 1}, {:max, 10_000}]})

      for {value, expected} <- [
            {"10000", []},
            {"10,000.01", [{:max, 10_000}]},
            {Decimal.new("0.5"), [{:min, 1}]},
            {7, []},
            {"$9,999.99", []}
          ] do
        assert validate([line(%{"line_total" => value})], shape)
               |> issues()
               |> Enum.map(& &1.rule) ==
                 expected
      end
    end

    test "min and max compare dates" do
      shape =
        invoice(columns: %{"description" => [{:min, ~D[2026-10-01]}, {:max, ~D[2026-10-31]}]})

      assert validate([line(%{"description" => "2026-10-15"})], shape) |> issues() == []

      assert [%{rule: {:max, ~D[2026-10-31]}}] =
               validate([line(%{"description" => ~D[2026-11-01]})], shape) |> issues()
    end

    test "in takes one of a list, compared as text" do
      shape = invoice(columns: %{"qty" => [{:in, ["1", "2", "3"]}]})

      assert validate([line(%{"qty" => "2"})], shape) |> issues() == []
      assert validate([line(%{"qty" => Decimal.new("3")})], shape) |> issues() == []

      assert [%{rule: {:in, ["1", "2", "3"]}}] =
               validate([line(%{"qty" => "9"})], shape) |> issues()
    end

    test "type rules and regexes work as row rules do, on text and native cells" do
      shape = invoice(columns: %{"qty" => [:integer], "sku" => [~r/^[A-Z]-\d{3}$/]})

      assert validate([line(%{"qty" => Decimal.new("4"), "sku" => "C-300"})], shape) |> issues() ==
               []

      assert [%{column: "qty", rule: :integer}] =
               validate([line(%{"qty" => "1.5"})], shape) |> issues()
    end

    test "a named column rule is reported by its name" do
      shape = invoice(columns: %{"sku" => [{:known_sku, &String.starts_with?(&1, "A-")}]})

      assert [%{column: "sku", rule: :known_sku}] =
               validate([line(%{"sku" => "B-200"})], shape) |> issues()
    end

    test "a failing row rule is reported by its name, with no column" do
      row = line(%{"qty" => "3", "unit_price" => "12.50", "line_total" => "25.00"})

      assert [{:invalid, ^row, [%{line: 1, column: nil, rule: :line_total_adds_up}]}] =
               validate([row])
    end

    test "a row rule that raises counts as failed" do
      row = line(%{"unit_price" => ""})

      assert [{:invalid, ^row, [%{column: nil, rule: :line_total_adds_up}]}] = validate([row])
    end

    test "column issues come before row issues" do
      row = line(%{"sku" => "bad", "qty" => "3"})

      assert [%{column: "sku"}, %{column: nil, rule: :line_total_adds_up}] =
               validate([row]) |> issues()
    end

    test "issues carry no cell values unless values: true" do
      row = line(%{"line_total" => "12500.00", "unit_price" => "6250.00"})

      assert [%{value: nil}] = validate([row]) |> issues()
      assert [%{value: "12500.00"}] = validate([row], invoice(), values: true) |> issues()
    end

    test "rows are read only when the result is read" do
      rows = Stream.map([line(%{})], &tap(&1, fn _row -> send(self(), :read) end))

      result = Validate.rows(rows, invoice())
      refute_received :read

      assert [{:ok, _row}] = Enum.to_list(result)
      assert_received :read
    end

    test "a shape without validation passes every row" do
      shape = Shape.new(name: "plain", spec: spec())

      assert validate([line(%{"sku" => "anything"})], shape) == [
               {:ok, line(%{"sku" => "anything"})}
             ]
    end

    test "the shape can be a module" do
      assert [{:invalid, _row, [_issue]}] = validate([line(%{"sku" => "bad"})], Invoice)
    end

    test "unknown options raise" do
      assert_raise ArgumentError, ~r/colour/, fn ->
        validate([line(%{})], invoice(), colour: :blue)
      end
    end
  end

  describe "Shape.new/1 validation:" do
    test "a shape keeps its validation" do
      assert %{columns: %{"sku" => [:required, _regex]}, rows: [{:line_total_adds_up, _fun}]} =
               invoice().validation
    end

    test "validation is optional" do
      assert %{columns: %{}, rows: []} = Shape.new(name: "plain", spec: spec()).validation
    end

    test "a rule for a column the shape does not have raises naming it" do
      assert_raise ArgumentError, ~r/colour/, fn ->
        invoice(columns: %{"colour" => [:required]})
      end
    end

    test "an unknown rule raises" do
      for rule <- [
            :shiny,
            {:max, "ten"},
            {:in, "a"},
            {"name", &is_binary/1},
            {:named, &Kernel.+/2}
          ] do
        assert_raise ArgumentError, ~r/rule/, fn -> invoice(columns: %{"sku" => [rule]}) end
      end
    end

    test "a function rule must be named, so issues can report it" do
      message = ~r/function rule must be named/

      assert_raise ArgumentError, message, fn -> invoice(columns: %{"sku" => [&is_binary/1]}) end

      assert_raise ArgumentError, message, fn ->
        Shape.new(
          name: "form",
          spec: spec(),
          fields: %{"total" => [at: "B1", rules: [&is_binary/1]]}
        )
      end
    end

    test "a row rule must be a name and a one argument function" do
      for rule <- [&is_map/1, {:ok, :not_a_fun}, {"name", &is_map/1}] do
        assert_raise ArgumentError, ~r/row rule/, fn -> invoice(rows: [rule]) end
      end
    end

    test "unknown validation keys raise" do
      assert_raise ArgumentError, ~r/colour/, fn -> invoice(colour: %{}) end
    end
  end

  describe "Shape.from_map/1 validation" do
    test "column rules come from the map, rows stay elixir only" do
      map = %{
        "name" => "invoice",
        "header" => %{
          "columns" => %{"sku" => ["sku"], "qty" => ["qty"], "line_total" => ["line total"]}
        },
        "validation" => %{
          "columns" => %{
            "sku" => ["required", "/^[A-Z]-\\d{3}$/"],
            "qty" => ["integer", %{"min" => 1}],
            "line_total" => ["required", "number", %{"max" => 10_000}, %{"in" => ["1", "2"]}]
          }
        }
      }

      assert {:ok, shape} = Shape.from_map(map)
      assert %{columns: columns, rows: []} = shape.validation
      assert [:required, %Regex{}] = columns["sku"]
      assert columns["qty"] == [:integer, {:min, 1}]
      assert columns["line_total"] == [:required, :number, {:max, 10_000}, {:in, ["1", "2"]}]
    end

    test "an unknown rule in the map is an error naming where" do
      map = %{
        "name" => "invoice",
        "header" => %{"columns" => %{"sku" => ["sku"]}},
        "validation" => %{"columns" => %{"sku" => ["shiny"]}}
      }

      assert {:error, {:invalid_value, {"validation.columns.sku", "shiny"}}} = Shape.from_map(map)
    end

    test "a rule for a column the shape does not have is an error, not a raise" do
      map = %{
        "name" => "invoice",
        "header" => %{"columns" => %{"sku" => ["sku"]}},
        "validation" => %{"columns" => %{"colour" => ["required"]}}
      }

      assert {:error, {:invalid_shape, message}} = Shape.from_map(map)
      assert message =~ "colour"
    end
  end

  describe "reader validate/3" do
    defp recognised do
      Shape.new(
        name: "invoice",
        spec:
          Table.spec(
            header: [columns: @columns],
            row: [match: %{"qty" => :number, "line_total" => :number}],
            stop: [{:contains, ~r/^total/i}]
          ),
        validation: [
          columns: %{
            "sku" => [:required],
            "unit_price" => [:number],
            "line_total" => [:required, :number, {:max, 10_000}]
          }
        ]
      )
    end

    defp csv(lines), do: {:string, Enum.join(lines, "\n") <> "\n"}

    defp invoice_csv(rows) do
      csv(
        [
          "ACME PTY LTD - Tax Invoice,,,,",
          "Invoice No,INV-1001,,,",
          ",,,,",
          "SKU,Description,Qty,Unit Price,Line Total"
        ] ++ rows ++ ["Total,,,,"]
      )
    end

    test "a known file with a line over the limit is invalid, naming its source line" do
      source =
        invoice_csv([
          "A-100,widget,2,12.50,25.00",
          "C-300,press,1,12500.00,12500.00",
          "B-200,gadget,4,99.00,396.00"
        ])

      assert {:ok, result} = CSV.validate(source, recognised())

      refute result.valid
      assert result.rows == 3
      assert [%{line: 6, column: "line_total", rule: {:max, 10_000}}] = result.issues
    end

    test "a file whose content passes is valid" do
      assert {:ok, result} =
               CSV.validate(invoice_csv(["A-100,widget,2,12.50,25.00"]), recognised())

      assert result.valid
      assert result.rows == 1
      assert result.issues == []
    end

    test "a value failing recognition does not cut the table, rows after it are checked" do
      source =
        invoice_csv([
          "A-100,widget,2,12.50,25.00",
          "C-300,press,x,n/a,n/a",
          "B-200,gadget,4,99.00,12000.00"
        ])

      assert {:ok, result} = CSV.validate(source, recognised())

      assert result.rows == 3

      assert [
               %{line: 6, column: "line_total", rule: :number},
               %{line: 6, column: "qty", rule: {:recognition, :number}},
               %{line: 6, column: "unit_price", rule: :number},
               %{line: 7, column: "line_total", rule: {:max, 10_000}}
             ] = result.issues
    end

    test "a stop rule ends the table" do
      assert {:ok, result} =
               CSV.validate(invoice_csv(["A-100,widget,2,12.50,25.00"]), recognised())

      assert result.rows == 1
    end

    test "blank lines inside the table are skipped, lines stay the source lines" do
      source = invoice_csv(["A-100,widget,2,12.50,25.00", ",,,,", "B-200,gadget,1,,"])

      assert {:ok, result} = CSV.validate(source, recognised())

      assert result.rows == 2
      assert [%{line: 7, column: "line_total", rule: :required}] = result.issues
    end

    test "header_row: names the header line, within: bounds the search" do
      source = invoice_csv(["A-100,widget,2,12.50,25.00"])

      assert {:ok, %{valid: true}} = CSV.validate(source, recognised(), header_row: 4)
      assert {:error, {:header_not_found, _miss}} = CSV.validate(source, recognised(), within: 2)
    end

    test "a file without the shape's header is an error, as locate" do
      assert {:error, {:header_not_found, _miss}} =
               CSV.validate(csv(["name,colour", "fig,purple"]), recognised())
    end

    test "values: true puts the cell in the issue" do
      source = invoice_csv(["C-300,press,1,12500.00,12500.00"])

      assert {:ok, %{issues: [%{value: "12500.00"}]}} =
               CSV.validate(source, recognised(), values: true)

      assert {:ok, %{issues: [%{value: nil}]}} = CSV.validate(source, recognised())
    end

    test "the shape can be a module" do
      assert {:ok, %{valid: true}} =
               CSV.validate(
                 csv(["SKU,Description,Qty,Unit Price,Line Total", "A-100,widget,2,12.50,25.00"]),
                 Invoice
               )
    end

    test "a source that cannot be read is an error" do
      assert {:error, :enoent} = CSV.validate("missing.csv", recognised())
    end

    test "a recognition rule on an optional column the file lacks reports nothing" do
      shape =
        Shape.new(
          name: "invoice",
          spec:
            Table.spec(
              header: [columns: @columns, required: ["sku", "line_total"], min_matches: 2],
              row: [match: %{"qty" => :number, "line_total" => :number}]
            ),
          validation: [columns: %{"line_total" => [{:max, 10_000}]}]
        )

      source = csv(["SKU,Line Total", "A-100,25.00", "B-200,396.00"])

      assert {:ok, %{valid: true, rows: 2, issues: []}} = CSV.validate(source, shape)
    end

    test "a :required rule on an optional column the file lacks fails every row" do
      shape =
        Shape.new(
          name: "invoice",
          spec:
            Table.spec(
              header: [columns: @columns, required: ["sku", "line_total"], min_matches: 2],
              row: [match: %{"qty" => :number, "line_total" => :number}]
            ),
          validation: [columns: %{"qty" => [:required, :integer]}]
        )

      source = csv(["SKU,Line Total", "A-100,25.00", "B-200,396.00"])

      assert {:ok, %{valid: false, rows: 2, issues: issues}} = CSV.validate(source, shape)

      assert [
               %{line: 2, column: "qty", rule: :required},
               %{line: 3, column: "qty", rule: :required}
             ] = issues
    end

    test "a nil cell in the table fails :required" do
      shape =
        Shape.new(name: "invoice", spec: spec(), validation: [columns: %{"sku" => [:required]}])

      raw = [
        ["sku", "description", "qty", "unit price", "line total"],
        [nil, "widget", "2", "12.50", "25.00"],
        ["B-200", "gadget", "1", "396.00", "396.00"]
      ]

      assert {:ok, %{valid: false, issues: [%{line: 2, column: "sku", rule: :required}]}} =
               Validate.source(raw, shape, [])
    end

    test "a malformed file is a parse error" do
      source =
        {:string, "SKU,Description,Qty,Unit Price,Line Total\nA-100,\"widget,2,12.50,25.00\n"}

      assert {:error, {:parse_error, _message}} = CSV.validate(source, recognised())
    end
  end
end
