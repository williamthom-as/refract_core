defmodule Refract.Validate.RecordTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 10_000

  alias Refract.CSV
  alias Refract.Shape
  alias Refract.Table
  alias Refract.Validate
  alias Refract.Validate.Issue

  @columns %{
    "order_no" => ["order no"],
    "line_no" => ["line no"],
    "qty" => ["qty"],
    "line_total" => ["line total"]
  }

  defp shape(validation, opts \\ []) do
    Shape.new(
      name: "order",
      spec:
        Table.spec(
          header: [
            columns: @columns,
            required: ["order_no"],
            min_matches: Keyword.get(opts, :min_matches, 4)
          ],
          stop: [:blank]
        ),
      validation: validation,
      fields: Keyword.get(opts, :fields, %{})
    )
  end

  defp lines do
    shape(
      columns: %{"qty" => [:required, :integer], "line_total" => [:number]},
      rows: [{:has_total, &(&1["line_total"] not in [nil, ""])}]
    )
  end

  defp row(order_no, line_no, qty, line_total \\ "1.00"),
    do: %{"order_no" => order_no, "line_no" => line_no, "qty" => qty, "line_total" => line_total}

  defp tagged(rows, opts \\ []), do: rows |> Validate.rows(lines(), opts) |> Enum.to_list()

  defp csv(lines), do: {:string, Enum.join(lines, "\n") <> "\n"}

  defp describe_issue(fields), do: Issue.describe(struct!(Issue, fields))

  describe "Validate.rows/3 identify_by:" do
    test "every issue of a row carries the record it is about" do
      rows = [row("SO-7", "1", "2"), row("SO-7", "2", "x", "")]

      assert [{:ok, _first}, {:invalid, _row, issues}] = tagged(rows, identify_by: "order_no")

      assert [
               %{line: 2, column: "qty", rule: :integer, record: %{"order_no" => "SO-7"}},
               %{line: 2, column: nil, rule: :has_total, record: %{"order_no" => "SO-7"}}
             ] = issues
    end

    test "several columns identify a row together" do
      rows = [row("SO-7", "2", "x")]

      assert [{:invalid, _row, [issue]}] = tagged(rows, identify_by: ["order_no", "line_no"])
      assert %{record: %{"order_no" => "SO-7", "line_no" => "2"}} = issue
    end

    test "one column is the same as a list of one" do
      rows = [row("SO-7", "2", "x")]

      assert tagged(rows, identify_by: "order_no") == tagged(rows, identify_by: ["order_no"])
    end

    test "no record by default" do
      assert [{:invalid, _row, [%{record: nil}]}] = tagged([row("SO-7", "1", "x")])
    end

    test "a column the row lacks is nil in the record" do
      rows = [%{"order_no" => "SO-7", "qty" => "x", "line_total" => "1"}]

      assert [{:invalid, _row, [%{record: %{"order_no" => "SO-7", "line_no" => nil}}]}] =
               tagged(rows, identify_by: ["order_no", "line_no"])
    end

    test "the record shows without values: true, the value does not" do
      assert [{:invalid, _row, [%{record: %{"order_no" => "SO-7"}, value: nil}]}] =
               tagged([row("SO-7", "1", "x")], identify_by: "order_no")
    end

    test "identify_by must be a column name or a non empty list of them" do
      for identify_by <- [:order_no, [], ["order_no", :line_no], 1] do
        assert_raise ArgumentError, ~r/identify_by must be a column name or a list/, fn ->
          Validate.rows([], lines(), identify_by: identify_by)
        end
      end
    end
  end

  describe "reader validate/3 identify_by:" do
    test "issues on table rows carry their record, lines stay source lines" do
      source =
        csv([
          "ACME PTY LTD,,,",
          "Order No,Line No,Qty,Line Total",
          "SO-7,1,2,25.00",
          "SO-7,2,x,12.00",
          "SO-8,1,1,"
        ])

      assert {:ok, %Validate.Result{issues: issues}} =
               CSV.validate(source, lines(), identify_by: ["order_no", "line_no"])

      assert [
               %{line: 4, column: "qty", record: %{"order_no" => "SO-7", "line_no" => "2"}},
               %{line: 5, rule: :has_total, record: %{"order_no" => "SO-8", "line_no" => "1"}}
             ] = issues
    end

    test "a recognition issue carries its record" do
      shape =
        Shape.new(
          name: "order",
          spec: Table.spec(header: [columns: @columns], row: [match: %{"line_total" => :number}]),
          validation: [columns: %{}]
        )

      source = csv(["Order No,Line No,Qty,Line Total", "SO-7,1,2,n/a"])

      assert {:ok, %Validate.Result{issues: [issue]}} =
               CSV.validate(source, shape, identify_by: "order_no")

      assert %{rule: {:recognition, :number}, record: %{"order_no" => "SO-7"}} = issue
    end

    test "a missing column at the header has no record" do
      shape = shape([columns: %{"qty" => [:required]}], min_matches: 3)
      source = csv(["Order No,Line No,Line Total", "SO-7,1,25.00"])

      assert {:ok, %Validate.Result{issues: [issue]}} =
               CSV.validate(source, shape, identify_by: "order_no")

      assert %{rule: :column_missing, record: nil} = issue
    end

    test "field and document issues have no record, row issues do" do
      shape =
        shape(
          [
            columns: %{"qty" => [:integer]},
            document: [{:never, fn _document -> false end}]
          ],
          fields: %{"customer" => [label: "customer", rules: [:required]]}
        )

      source = csv(["Customer,,,", ",,,", "Order No,Line No,Qty,Line Total", "SO-7,1,x,25.00"])

      assert {:ok, %Validate.Result{issues: issues}} =
               CSV.validate(source, shape, identify_by: "order_no")

      assert [
               %{field: "customer", record: nil},
               %{column: "qty", record: %{"order_no" => "SO-7"}},
               %{rule: :never, record: nil}
             ] = issues
    end

    test "identify_by: is checked" do
      assert_raise ArgumentError, ~r/identify_by must be a column name or a list/, fn ->
        CSV.validate(csv(["Order No,Line No,Qty,Line Total"]), lines(), identify_by: 1)
      end
    end
  end

  describe "Issue.describe/1 with a record" do
    test "the record follows the line" do
      assert describe_issue(
               line: 3,
               column: "qty",
               rule: :integer,
               record: %{"account" => "A-1042"}
             ) == "line 3 (account A-1042), qty: must be an integer"
    end

    test "several columns read by name" do
      assert describe_issue(
               line: 3,
               column: "qty",
               rule: :integer,
               record: %{"order_no" => "SO-7", "line_no" => 2}
             ) == "line 3 (line_no 2, order_no SO-7), qty: must be an integer"
    end

    test "a row rule issue" do
      assert describe_issue(line: 5, rule: :totals_match, record: %{"id" => 7}) ==
               "line 5 (id 7): fails totals_match"
    end

    test "typed values read as text, nil as nothing" do
      assert describe_issue(
               line: 2,
               column: "qty",
               rule: :required,
               record: %{"opened" => ~D[2024-01-31], "branch" => nil}
             ) == "line 2 (branch , opened 2024-01-31), qty: is required"
    end

    test "no record reads as before" do
      assert describe_issue(line: 3, column: "account", rule: :required) ==
               "line 3, account: is required"
    end
  end

  describe "Validate.Result.to_map/1 with a record" do
    test "the record is its columns with values as text" do
      result = %Validate.Result{
        valid: false,
        rows: 1,
        issues: [
          struct!(Issue,
            line: 4,
            column: "qty",
            rule: :integer,
            record: %{"order_no" => "SO-7", "amount" => Decimal.new("12.50")}
          ),
          %Issue{rule: :never}
        ]
      }

      assert %{
               issues: [
                 %{record: %{"order_no" => "SO-7", "amount" => "12.50"}},
                 %{record: nil}
               ]
             } = Validate.Result.to_map(result)
    end
  end
end
