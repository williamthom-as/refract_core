defmodule Refract.TableTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  alias Refract.Table

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

    test "raises when min_score is outside 0 to 1" do
      assert_raise ArgumentError, fn -> row_spec(match: @rules, min_score: 1.5) end
      assert_raise ArgumentError, fn -> row_spec(match: @rules, min_score: -0.1) end
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

    test "regex rules match the cell" do
      assert passes?(~r/^[A-Z]{3}\d{3}$/, "ABC123")
      refute passes?(~r/^[A-Z]{3}\d{3}$/, "Subtotal")
    end

    test "function rules pass on a truthy result" do
      assert passes?(&(&1 == "apple"), "apple")
      refute passes?(&(&1 == "apple"), "pear")
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
end
