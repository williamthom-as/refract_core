defmodule Refract.TableTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  @moduletag timeout: 5_000

  alias Refract.Table
  alias Refract.Table.Report.Column
  alias Refract.Table.Report.Line
  alias Refract.Table.Report.Rule
  alias Refract.Table.Spec.Row

  @columns %{
    "vendor" => ["vendor", "supplier"],
    "sku" => ["sku", "product code", ~r/^item\s*no/i],
    "item" => ["item", "description"],
    "cost_per_kg" => ["cost/kg", "unit price"],
    "kg" => ["kg", "qty"],
    "total" => ["line total", "amount"]
  }

  defp invoice_spec(header_opts \\ []) do
    defaults = [columns: @columns, required: ["sku", "total"], min_matches: 4]

    Table.spec(header: Keyword.merge(defaults, header_opts))
  end

  @rules %{"sku" => :integer, "total" => :number}

  @line %{
    "vendor" => "ABC123",
    "sku" => "78632478",
    "item" => "apple",
    "cost_per_kg" => "1.5",
    "kg" => "2",
    "total" => "3"
  }

  @subtotal %{
    "vendor" => "",
    "sku" => "",
    "item" => "Subtotal",
    "cost_per_kg" => "",
    "kg" => "",
    "total" => "8"
  }

  defp row_spec(row_opts) do
    Table.spec(
      header: [columns: @columns, required: ["sku", "total"], min_matches: 4],
      row: row_opts
    )
  end

  @total_line ["", "", "", "", "", "", "Invoice Total", "9.5"]
  @blank_line ["", "", " ", "", "", "", "", ""]
  @raw_line ["", "ABC123", "1", "78632478", "apple", "1.5", "2", "3"]

  defp table_spec(opts) do
    Table.spec([header: [columns: @columns, required: ["sku", "total"], min_matches: 4]] ++ opts)
  end

  defp passes?(rule, value) do
    spec = Table.spec(header: [columns: %{"v" => ["v"]}], row: [match: %{"v" => rule}])

    Table.match_row(spec, %{"v" => value}) == :ok
  end

  describe "spec/1" do
    test "returns a spec" do
      assert %Table.Spec{} = invoice_spec()
    end

    test "header columns alone is enough" do
      spec = Table.spec(header: [columns: %{"id" => ["id"]}])

      assert {:ok, %{"id" => 0}} = Table.match_header(spec, ["id"])
    end

    test "no header columns raises" do
      assert_raise ArgumentError, ~r/at least one column/, fn ->
        Table.spec(header: [columns: %{}])
      end
    end

    test "a column with no aliases raises" do
      assert_raise ArgumentError, ~r/id/, fn ->
        Table.spec(header: [columns: %{"id" => [], "sku" => ["sku"]}])
      end
    end

    test "a column name that is not a string raises" do
      assert_raise ArgumentError, ~r/:sku/, fn ->
        Table.spec(header: [columns: %{sku: ["sku"]}])
      end
    end

    test "min_matches defaults to every column" do
      spec = Table.spec(header: [columns: %{"id" => ["id"], "name" => ["name"]}])

      assert {:error, _} = Table.match_header(spec, ["id"])
    end

    test "raises on an unknown option" do
      assert_raise ArgumentError, fn ->
        Table.spec(header: [columns: %{"id" => ["id"]}], bogus: 1)
      end
    end

    test "raises without header columns" do
      assert_raise ArgumentError, fn -> Table.spec(header: [required: ["id"]]) end
    end

    test "raises when a required column is not a header column" do
      assert_raise ArgumentError, fn ->
        Table.spec(header: [columns: %{"id" => ["id"]}, required: ["sku"]])
      end
    end

    test "raises when min_matches is more than the header columns" do
      assert_raise ArgumentError, fn ->
        Table.spec(header: [columns: %{"id" => ["id"]}, min_matches: 2])
      end
    end
  end

  describe "match_header/2" do
    test "maps canonical names to positions, ignoring columns the spec doesnt name" do
      row = ["", "Vendor", "Line", "SKU", "Item", "Cost/kg", "Kg", "Line Total"]

      assert Table.match_header(invoice_spec(), row) ==
               {:ok,
                %{
                  "vendor" => 1,
                  "sku" => 3,
                  "item" => 4,
                  "cost_per_kg" => 5,
                  "kg" => 6,
                  "total" => 7
                }}
    end

    test "ignores case and surrounding whitespace" do
      row = ["  sku ", "LINE TOTAL", "Vendor", "item"]

      assert Table.match_header(invoice_spec(), row) ==
               {:ok, %{"sku" => 0, "total" => 1, "vendor" => 2, "item" => 3}}
    end

    test "matches any alias" do
      row = ["", "Supplier", "Line", "Product Code", "Description", "Unit Price", "Qty", "Amount"]

      assert {:ok, %{"vendor" => 1, "sku" => 3, "total" => 7}} =
               Table.match_header(invoice_spec(), row)
    end

    test "matches regex aliases" do
      row = ["Item No.", "Description", "Amount"]

      assert Table.match_header(invoice_spec(min_matches: 3), row) ==
               {:ok, %{"sku" => 0, "item" => 1, "total" => 2}}
    end

    test "ignores literal wrapping quotes" do
      row = ["\"SKU\"", "\"Line Total\"", " \"Vendor\" ", "\"Item\""]

      assert Table.match_header(invoice_spec(), row) ==
               {:ok, %{"sku" => 0, "total" => 1, "vendor" => 2, "item" => 3}}
    end

    test "when several cells match a column the alias listed first wins, whatever the order" do
      spec = Table.spec(header: [columns: %{"cost" => ["total cost", "cost", "final price"]}])

      assert Table.match_header(spec, ["Final Price", "Cost", "Total Cost"]) ==
               {:ok, %{"cost" => 2}}

      assert Table.match_header(spec, ["Total Cost", "Final Price"]) == {:ok, %{"cost" => 0}}
      assert Table.match_header(spec, ["Final Price", "Cost"]) == {:ok, %{"cost" => 1}}
    end

    test "a column name not in its aliases outranks them, listed it ranks where it sits" do
      assert Table.match_header(Table.spec(header: [columns: %{"cost" => ["final price"]}]), [
               "Final Price",
               "Cost"
             ]) == {:ok, %{"cost" => 1}}

      assert Table.match_header(
               Table.spec(header: [columns: %{"cost" => ["final price", "cost"]}]),
               ["Cost", "Final Price"]
             ) == {:ok, %{"cost" => 1}}
    end

    test "regex aliases rank by their place among the regex aliases" do
      spec = Table.spec(header: [columns: %{"product" => [~r/^item\s*no/i, ~r/^sku/i]}])

      assert Table.match_header(spec, ["SKU", "Item No."]) == {:ok, %{"product" => 1}}
    end

    test "the other cells that matched a column are reported, the first alias used" do
      spec = Table.spec(header: [columns: %{"cost" => ["total cost", "cost", "final price"]}])

      assert [%Line{columns: %{"cost" => column}}] =
               Table.scan([["Final Price", "Cost", "Total Cost"]], spec)

      assert %Column{passed: true, index: 2, cell: "Total Cost"} = column
      assert column.others == [{0, "Final Price"}, {1, "Cost"}]
    end

    test "a column one cell matched reports no others" do
      assert [%Line{columns: %{"sku" => column}}] =
               Table.scan([["SKU", "Item", "Amount"]], invoice_spec(min_matches: 3))

      assert column.index == 0
      assert column.others == []
    end

    test "regex aliases ignore surrounding whitespace and literal wrapping quotes" do
      row = ["  Item No. ", "\"Item No\"", "Description", "Amount"]

      assert Table.match_header(invoice_spec(min_matches: 3), row) ==
               {:ok, %{"sku" => 0, "item" => 2, "total" => 3}}

      row = ["\"Item No\"", "Description", "Amount"]

      assert Table.match_header(invoice_spec(min_matches: 3), row) ==
               {:ok, %{"sku" => 0, "item" => 1, "total" => 2}}
    end

    test "a column matches its own name" do
      row = ["Total", "SKU", "cost_per_kg"]

      assert Table.match_header(invoice_spec(min_matches: 3), row) ==
               {:ok, %{"total" => 0, "sku" => 1, "cost_per_kg" => 2}}
    end

    test "missing a required column says what matched and what was missing" do
      row = ["Vendor", "SKU", "Item", "Cost/kg", "Kg"]

      assert {:error, %{matched: matched, missing: ["total"]}} =
               Table.match_header(invoice_spec(), row)

      assert Enum.sort(matched) == ["cost_per_kg", "item", "kg", "sku", "vendor"]
    end

    test "too few matches is an error even with every required column" do
      assert {:error, %{matched: matched, missing: []}} =
               Table.match_header(invoice_spec(), ["SKU", "Line Total"])

      assert Enum.sort(matched) == ["sku", "total"]
    end

    test "skips cells that are not strings" do
      row = [nil, "SKU", 2024, "Line Total", ~D[2010-01-01]]

      assert Table.match_header(invoice_spec(min_matches: 2), row) ==
               {:ok, %{"sku" => 1, "total" => 3}}
    end

    test "header-like words are not a match" do
      row = ["Bill To", "", "", "", "", "SKU list attached", "Total due", "see below"]

      assert {:error, %{matched: [], missing: missing}} = Table.match_header(invoice_spec(), row)
      assert Enum.sort(missing) == ["sku", "total"]
    end
  end

  describe "scan/2" do
    @header_line ["", "Vendor", "Line", "SKU", "Item", "Cost/kg", "Kg", "Line Total"]
    @decoy_line ["Summary", "SKU", "", "Line Total"]

    defp positions(report) do
      for {column, %{passed: true, index: index}} <- report.columns,
          into: %{},
          do: {column, index}
    end

    defp rule(report, name), do: Enum.find(report.rules, &(&1.rule == name))

    test "one report per line, numbered from 1" do
      assert [%Line{row: 1, check: :header}, %Line{row: 2}, %Line{row: 3}] =
               Table.scan([@blank_line, @header_line, @raw_line], invoice_spec())
    end

    test "a header report lists the non blank cells no column claimed" do
      assert [header] =
               Table.scan([["SKU", "Region", "", "Item", "Amount"]], invoice_spec(min_matches: 3))

      assert header.extra == [{1, "Region"}]
    end

    test "a header line passes and says where and how each column matched" do
      assert [_blank, header] = Table.scan([@blank_line, @header_line], invoice_spec())

      assert header.passed

      assert header.columns["sku"] == %Column{passed: true, index: 3, cell: "SKU", rule: "sku"}

      assert header.columns["total"] == %Column{
               passed: true,
               index: 7,
               cell: "Line Total",
               rule: "line total"
             }

      assert positions(header) == %{
               "vendor" => 1,
               "sku" => 3,
               "item" => 4,
               "cost_per_kg" => 5,
               "kg" => 6,
               "total" => 7
             }
    end

    test "a passing line reports every rule it passed" do
      assert [header] = Table.scan([@header_line], invoice_spec())

      assert header.rules == [
               %Rule{rule: :min_matches, passed: true, expected: 4, actual: 6},
               %Rule{rule: :required, passed: true, expected: ["sku", "total"], missing: []}
             ]
    end

    test "a failed line reports every column, matched or not" do
      assert [line] = Table.scan([@decoy_line], invoice_spec())

      refute line.passed
      assert positions(line) == %{"sku" => 1, "total" => 3}

      for column <- ["vendor", "item", "cost_per_kg", "kg"] do
        assert line.columns[column] == %Column{passed: false}
      end
    end

    test "a failed line says which rule failed, expected against actual" do
      assert [line] = Table.scan([@decoy_line], invoice_spec())

      assert rule(line, :min_matches) == %Rule{
               rule: :min_matches,
               passed: false,
               expected: 4,
               actual: 2
             }

      assert rule(line, :required).passed
    end

    test "a missing required column is named" do
      spec = invoice_spec(min_matches: 2)

      assert [line] = Table.scan([["SKU", "Kg", "Item"]], spec)

      refute line.passed
      assert rule(line, :min_matches).passed

      assert rule(line, :required) == %Rule{
               rule: :required,
               passed: false,
               expected: ["sku", "total"],
               missing: ["total"]
             }
    end

    test "a decoy line scores below the real header" do
      assert [decoy, header] = Table.scan([@decoy_line, @header_line], invoice_spec())
      assert rule(decoy, :min_matches).actual < rule(header, :min_matches).actual
    end

    test "a regex alias is the rule that matched" do
      line = ["Supplier", "Item No", "Description", "Unit Price", "Qty", "Amount"]

      assert [%{passed: true} = report] = Table.scan([line], invoice_spec())

      assert %Column{passed: true, index: 1, cell: "Item No", rule: %Regex{} = regex} =
               report.columns["sku"]

      assert Regex.source(regex) == "^item\\s*no"

      assert report.columns["vendor"] == %Column{
               passed: true,
               index: 0,
               cell: "Supplier",
               rule: "supplier"
             }
    end

    test "cells that are not strings never match" do
      assert [report] = Table.scan([[nil, 7, "SKU"]], invoice_spec())
      assert positions(report) == %{"sku" => 2}
    end

    test "the alias listed first wins, the other matching cells are kept" do
      assert [report] = Table.scan([["SKU", "Product Code"]], invoice_spec())

      assert report.columns["sku"] == %Column{
               passed: true,
               index: 0,
               cell: "SKU",
               rule: "sku",
               others: [{1, "Product Code"}]
             }
    end

    test "a plain alias beats a regex alias in the same column" do
      spec = Table.spec(header: [columns: %{"code" => [~r/^item/i, "item no"]}])

      assert [report] = Table.scan([["Item Code", "Item No"]], spec)

      assert report.columns["code"] == %Column{
               passed: true,
               index: 1,
               cell: "Item No",
               rule: "item no"
             }
    end

    test "a regex alias matches when no plain alias does" do
      spec = Table.spec(header: [columns: %{"code" => [~r/^item/i, "item no"]}])

      assert [report] = Table.scan([["Item Code", "Other"]], spec)

      assert %Column{passed: true, index: 0, cell: "Item Code", rule: %Regex{}} =
               report.columns["code"]
    end

    test "a cell matched by one column can still match another column" do
      spec = Table.spec(header: [columns: %{"sku" => ["sku"], "code" => [~r/^s/i]}])

      assert [report] = Table.scan([["SKU"]], spec)
      assert positions(report) == %{"sku" => 0, "code" => 0}
    end

    test "no lines gives no reports" do
      assert Table.scan([], invoice_spec()) == []
    end

    property "agrees with match_header on every line" do
      cells =
        member_of([
          "Vendor",
          "SKU",
          "Item No",
          "Description",
          "Kg",
          "Qty",
          "Line Total",
          "Amount",
          "",
          "junk",
          nil,
          7
        ])

      check all(
              lines <- list_of(list_of(cells, max_length: 8), max_length: 5),
              min_matches <- integer(0..6)
            ) do
        spec = invoice_spec(min_matches: min_matches)

        for {line, report} <- Enum.zip(lines, Table.scan(lines, spec)) do
          case Table.match_header(spec, line) do
            {:ok, matched} -> assert report.passed and positions(report) == matched
            {:error, _miss} -> refute report.passed
          end
        end
      end
    end
  end

  describe "spec/1 row:" do
    test "raises on an unknown row option" do
      assert_raise ArgumentError, fn -> row_spec(match: @rules, bogus: 1) end
    end

    test "raises when a rule names a column not in the header" do
      assert_raise ArgumentError, fn -> row_spec(match: %{"colour" => :integer}) end
    end

    test "raises on an unknown rule" do
      assert_raise ArgumentError, fn -> row_spec(match: %{"sku" => :uuid}) end
    end

    test "a function rule must be named, so a failure can report it" do
      assert_raise ArgumentError, ~r/function rule must be named/, fn ->
        row_spec(match: %{"sku" => &is_binary/1})
      end

      assert %{match: %{"sku" => {:text, _fun}}} =
               row_spec(match: %{"sku" => {:text, &is_binary/1}}).row
    end

    test "raises when min_score is outside 0 to 1" do
      assert_raise ArgumentError, fn -> row_spec(match: @rules, min_score: 1.5) end
      assert_raise ArgumentError, fn -> row_spec(match: @rules, min_score: -0.1) end
    end
  end

  describe "optional columns with row rules" do
    defp optional_spec do
      Table.spec(
        header: [
          columns: %{"sku" => ["sku"], "total" => ["total"], "shipped_on" => ["shipped on"]},
          required: ["sku", "total"],
          min_matches: 2
        ],
        row: [match: %{"total" => :number, "shipped_on" => :date}]
      )
    end

    test "a rule for a column the file does not have is skipped, rows are kept" do
      lines = [["sku", "total"], ["A-100", "3.50"], ["B-200", "4.25"]]

      assert {:ok, table} = Table.locate(lines, optional_spec(), on_miss: :skip)

      assert Enum.to_list(table.rows) == [
               %{"sku" => "A-100", "total" => "3.50", "shipped_on" => nil},
               %{"sku" => "B-200", "total" => "4.25", "shipped_on" => nil}
             ]
    end

    test "the column present but blank still fails its rule" do
      lines = [["sku", "total", "shipped on"], ["A-100", "3.50", ""]]

      assert {:ok, table} = Table.locate(lines, optional_spec(), on_miss: :skip)
      assert Enum.to_list(table.rows) == []
    end

    test "match_row skips a rule for a column the row does not have" do
      assert Table.match_row(optional_spec(), %{"sku" => "A-100", "total" => "3.50"}) == :ok

      assert {:error, %{failed: [{"shipped_on", :date}]}} =
               Table.match_row(optional_spec(), %{"total" => "3.50", "shipped_on" => nil})
    end
  end

  describe "match_row/2" do
    test "passes when every rule passes" do
      assert Table.match_row(row_spec(match: @rules), @line) == :ok
    end

    test "no rules means every row passes" do
      assert Table.match_row(invoice_spec(), @subtotal) == :ok
    end

    test "a failed rule says which column and rule failed, and the score" do
      assert Table.match_row(row_spec(match: @rules), @subtotal) ==
               {:error, %{score: 0.5, failed: [{"sku", :integer}]}}
    end

    test "min_score defaults to every rule passing" do
      assert {:error, _} = Table.match_row(row_spec(match: @rules), @subtotal)
    end

    test "min_score lets some rules fail" do
      assert Table.match_row(row_spec(match: @rules, min_score: 0.5), @subtotal) == :ok
    end

    test "a missing cell fails its rule" do
      assert {:error, %{failed: [{"sku", :integer}]}} =
               Table.match_row(row_spec(match: @rules), Map.put(@line, "sku", nil))
    end

    test ":integer" do
      assert passes?(:integer, "78632478")
      assert passes?(:integer, "-3")
      refute passes?(:integer, "1.5")
      refute passes?(:integer, "12a")
      refute passes?(:integer, "")
    end

    test ":integer takes a whole decimal" do
      assert passes?(:integer, Decimal.new("1"))
      assert passes?(:integer, Decimal.new("1.0"))
      refute passes?(:integer, Decimal.new("1.5"))
    end

    test ":number" do
      assert passes?(:number, "3")
      assert passes?(:number, "1.5")
      assert passes?(:number, "-2.5")
      refute passes?(:number, "abc")
      refute passes?(:number, "")
    end

    test ":date takes iso dates" do
      assert passes?(:date, "2010-01-01")
      refute passes?(:date, "2010-13-01")
      refute passes?(:date, "not a date")
    end

    test "rules fail rather than crash on cells of another type" do
      refute passes?(:integer, 1.5)
      refute passes?(:number, ~D[2010-01-01])
      refute passes?(:date, 12)
    end

    test ":number parses like Parse.number" do
      assert passes?(:number, "1,234.56")
      assert passes?(:number, " 3 ")
      assert passes?(:number, Decimal.new("1.5"))
    end

    test ":date parses like Parse.date" do
      assert passes?(:date, "2010/01/01")
      assert passes?(:date, "2010-01-01T09:30:00Z")
      assert passes?(:date, ~N[2010-01-01 09:30:00])
      refute passes?(:date, "01/02/2010")
    end

    test ":datetime needs a time and parses like Parse.datetime" do
      assert passes?(:datetime, "2010-01-01 09:30:00")
      assert passes?(:datetime, "2010/01/01 9:30")
      assert passes?(:datetime, ~N[2010-01-01 09:30:00])
      refute passes?(:datetime, "2010-01-01")
      refute passes?(:datetime, ~D[2010-01-01])
      refute passes?(:datetime, "01/02/2010 9:30")
      refute passes?(:datetime, "not a time")
    end

    test ":datetime accepts any offset, so offset rows still match" do
      assert passes?(:datetime, "2010-01-01T09:30:00+10:00")
      assert passes?(:datetime, "2010-01-01T09:30:00Z")
    end

    test "regex rules match the cell" do
      assert passes?(~r/^[A-Z]{3}\d{3}$/, "ABC123")
      refute passes?(~r/^[A-Z]{3}\d{3}$/, "Subtotal")
    end

    test "regex rules match a native cell by its text" do
      assert passes?(~r/^\d{12}$/, Decimal.new("123456789012"))
      assert passes?(~r/^\d{12}$/, Decimal.new("1.23456789012E+11"))
      assert passes?(~r/^\d{12}$/, 123_456_789_012)
      assert passes?(~r/^-?\d+\.\d+$/, 1.5)
      assert passes?(~r/^2026-10-21$/, ~D[2026-10-21])
      assert passes?(~r/^2026-10-21T09:30:00$/, ~N[2026-10-21 09:30:00])
      assert passes?(~r/^09:30:00$/, ~T[09:30:00])
      assert passes?(~r/^true$/, true)
    end

    test "regex rules still fail a blank cell" do
      refute passes?(~r/.*/, nil)
    end

    test "named function rules pass on a truthy result" do
      assert passes?({:apple, &(&1 == "apple")}, "apple")
      refute passes?({:apple, &(&1 == "apple")}, "pear")
    end
  end

  describe "row report" do
    defp row_report(row_opts, row, opts \\ []) do
      Row.report(row_spec(row_opts).row, row, opts)
    end

    test "a passing row reports each rule and the score" do
      report = row_report([match: @rules], @line)

      assert %Line{check: :row, row: nil, passed: true} = report
      assert report.columns["sku"] == %Column{passed: true, rule: :integer}
      assert report.columns["total"] == %Column{passed: true, rule: :number}

      assert report.rules == [%Rule{rule: :min_score, passed: true, expected: 1.0, actual: 1.0}]
    end

    test "a failing row names the column and rule that failed" do
      report = row_report([match: @rules], @subtotal)

      refute report.passed
      assert report.columns["sku"] == %Column{passed: false, rule: :integer}
      assert report.columns["total"] == %Column{passed: true, rule: :number}

      assert report.rules == [%Rule{rule: :min_score, passed: false, expected: 1.0, actual: 0.5}]
    end

    test "min_score lets a row pass and still shows what failed" do
      report = row_report([match: @rules, min_score: 0.5], @subtotal)

      assert report.passed
      assert report.columns["sku"].passed == false
      assert [%Rule{rule: :min_score, passed: true, expected: 0.5, actual: 0.5}] = report.rules
    end

    test "only the columns with rules are reported" do
      report = row_report([match: @rules], @line)

      assert Map.keys(report.columns) == ["sku", "total"]
    end

    test "cells are left out by default" do
      report = row_report([match: @rules], @subtotal)

      assert Enum.all?(report.columns, fn {_column, column} -> column.cell == nil end)
    end

    test "values: true keeps the cells, passed or not" do
      report = row_report([match: @rules], @subtotal, values: true)

      assert report.columns["sku"] == %Column{passed: false, rule: :integer, cell: ""}
      assert report.columns["total"] == %Column{passed: true, rule: :number, cell: "8"}
    end

    test "a nil cell fails its rule" do
      report = row_report([match: @rules], Map.put(@line, "sku", nil), values: true)

      assert report.columns["sku"] == %Column{passed: false, rule: :integer, cell: nil}
    end

    test "a rule for a column the row does not have is skipped" do
      report = row_report([match: @rules], Map.delete(@line, "sku"), values: true)

      refute Map.has_key?(report.columns, "sku")
      assert report.passed
    end

    test "no rules passes with nothing to report" do
      assert %Line{check: :row, passed: true, columns: columns, rules: []} =
               row_report([], @subtotal)

      assert columns == %{}
    end

    test "unknown option raises" do
      assert_raise ArgumentError, fn -> row_report([match: @rules], @line, vaules: true) end
    end

    test "values must be a boolean" do
      assert_raise ArgumentError, ~r/values/, fn ->
        row_report([match: @rules], @line, values: "yes")
      end

      assert_raise ArgumentError, ~r/values/, fn -> row_report([], @line, values: "yes") end
    end

    property "agrees with match_row" do
      cells = member_of(["1", "-3", "1.5", "abc", "", nil, "2010-01-01"])

      check all(
              sku <- cells,
              total <- cells,
              min_score <- member_of([0.0, 0.5, 1.0])
            ) do
        spec = row_spec(match: @rules, min_score: min_score)
        row = %{@line | "sku" => sku, "total" => total}
        report = Row.report(spec.row, row)

        case Table.match_row(spec, row) do
          :ok ->
            assert report.passed

          {:error, %{score: score, failed: failed}} ->
            refute report.passed
            assert [%Rule{actual: ^score}] = report.rules

            assert Enum.sort(failed) ==
                     for(
                       {column, %Column{passed: false, rule: rule}} <- report.columns,
                       do: {column, rule}
                     )
        end
      end
    end
  end

  describe "spec/1 stop: and max_misses:" do
    test "raises on an unknown stop condition" do
      assert_raise ArgumentError, fn -> table_spec(stop: [:eof]) end
    end

    test "raises when stop is not a list" do
      assert_raise ArgumentError, fn -> table_spec(stop: :blank) end
    end

    test "raises when max_misses is not a non negative integer" do
      assert_raise ArgumentError, fn -> table_spec(max_misses: -1) end
      assert_raise ArgumentError, fn -> table_spec(max_misses: 1.5) end
    end

    test "accepts max_misses" do
      assert %Table.Spec{} = table_spec(max_misses: 1)
    end
  end

  describe "match_stop/2" do
    test "no stop conditions never stops" do
      assert Table.match_stop(invoice_spec(), @blank_line) == :continue
    end

    test "a data line does not stop" do
      spec = table_spec(stop: [:blank, {:contains, ~r/invoice total/i}])

      assert Table.match_stop(spec, @raw_line) == :continue
    end

    test ":blank stops on a line of empty or whitespace cells" do
      assert Table.match_stop(table_spec(stop: [:blank]), @blank_line) == {:stop, :blank}
    end

    test ":blank stops on nil cells and on an empty line" do
      spec = table_spec(stop: [:blank])

      assert Table.match_stop(spec, [nil, "", nil]) == {:stop, :blank}
      assert Table.match_stop(spec, []) == {:stop, :blank}
    end

    test ":blank does not stop when any cell has content" do
      assert Table.match_stop(table_spec(stop: [:blank]), @total_line) == :continue
    end

    test "{:contains, regex} stops when any cell matches" do
      condition = {:contains, ~r/invoice total/i}

      assert Table.match_stop(table_spec(stop: [condition]), @total_line) == {:stop, condition}
    end

    test "{:contains, regex} skips nil cells" do
      condition = {:contains, ~r/invoice total/i}
      spec = table_spec(stop: [condition])

      assert Table.match_stop(spec, [nil, "Invoice Total", nil]) == {:stop, condition}
      assert Table.match_stop(spec, [nil, "apple"]) == :continue
    end

    test "a function stops when it returns truthy" do
      condition = &(length(&1) < 3)
      spec = table_spec(stop: [condition])

      assert Table.match_stop(spec, ["a", "b"]) == {:stop, condition}
      assert Table.match_stop(spec, @raw_line) == :continue
    end

    test "a function returning a value that is not a boolean" do
      condition = fn row -> Enum.find(row, &(&1 == "END")) end
      spec = table_spec(stop: [condition])

      assert Table.match_stop(spec, ["", "END"]) == {:stop, condition}
      assert Table.match_stop(spec, @raw_line) == :continue
    end

    test "the first matching condition is the reason" do
      condition = {:contains, ~r/^$/}
      spec = table_spec(stop: [condition, :blank])

      assert Table.match_stop(spec, @blank_line) == {:stop, condition}
    end
  end

  describe "concat/1" do
    defp page(header, rows), do: Table.new(3, header, %{"id" => 0}, rows)

    test "rows of every table in order under one header" do
      table =
        Table.concat([
          page(["id", "name"], [%{"id" => "1", "name" => "alice"}]),
          page(["id", "name"], [%{"id" => "2", "name" => "bob"}, %{"id" => "3", "name" => "cy"}])
        ])

      assert table.header == ["id", "name"]

      assert Enum.to_list(table.rows) == [
               %{"id" => "1", "name" => "alice"},
               %{"id" => "2", "name" => "bob"},
               %{"id" => "3", "name" => "cy"}
             ]
    end

    test "the header is every column in first seen order, a missing column is nil" do
      table =
        Table.concat([
          page(["id", "name"], [%{"id" => "1", "name" => "alice"}]),
          page(["age", "id"], [%{"age" => "40", "id" => "2"}])
        ])

      assert table.header == ["id", "name", "age"]

      assert Enum.to_list(table.rows) == [
               %{"id" => "1", "name" => "alice", "age" => nil},
               %{"id" => "2", "name" => nil, "age" => "40"}
             ]
    end

    test "rows are read only when the table is read" do
      rows = Stream.map([%{"id" => "1"}], &tap(&1, fn _row -> send(self(), :read) end))

      table = Table.concat([page(["id"], rows), page(["id"], [%{"id" => "2"}])])
      refute_received :read

      assert Enum.to_list(table.rows) == [%{"id" => "1"}, %{"id" => "2"}]
      assert_received :read
    end

    test "the header row and source positions do not carry over" do
      table = Table.concat([page(["id"], [%{"id" => "1"}])])

      assert table.header_row == nil
      assert table.columns == %{}
    end

    test "no tables gives an empty table" do
      table = Table.concat([])

      assert table.header == []
      assert Enum.to_list(table.rows) == []
    end

    test "located tables from several sources read as one" do
      spec = Table.spec(header: [columns: %{"sku" => ["sku", "item no"], "total" => ["total"]}])

      {:ok, first} = Refract.CSV.locate({:string, "sku,total\n1,3\n"}, spec)
      {:ok, second} = Refract.CSV.locate({:string, "report\nitem no,total\n2,4\n"}, spec)

      table = Table.concat([first, second])

      assert Enum.to_list(table.rows) == [
               %{"sku" => "1", "total" => "3"},
               %{"sku" => "2", "total" => "4"}
             ]
    end

    test "anything but a list of tables raises" do
      for tables <- [:pages, page(["id"], []), [page(["id"], []), %{"id" => "1"}]] do
        assert_raise ArgumentError, ~r/tables/, fn -> Table.concat(tables) end
      end
    end
  end
end
