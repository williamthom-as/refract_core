defmodule Refract.Validate.UniqueTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 10_000

  alias Refract.CSV
  alias Refract.Shape
  alias Refract.Table
  alias Refract.Validate
  alias Refract.Validate.Issue

  @columns %{
    "account" => ["account"],
    "order_no" => ["order no"],
    "line_no" => ["line no"],
    "qty" => ["qty"]
  }

  defp shape(validation, opts \\ []) do
    Shape.new(
      name: "orders",
      spec: Table.spec(header: [columns: @columns, min_matches: 1], stop: [:blank]),
      validation: validation,
      fields: Keyword.get(opts, :fields, %{})
    )
  end

  defp accounts, do: shape(columns: %{"account" => [:unique]})

  defp lines, do: shape(unique: [["order_no", "line_no"]])

  defp row(fields),
    do: Map.merge(%{"account" => nil, "order_no" => nil, "line_no" => nil, "qty" => "1"}, fields)

  defp issues(rows, shape, opts \\ []) do
    rows
    |> Validate.rows(shape, opts)
    |> Enum.flat_map(fn
      {:ok, _row} -> []
      {:invalid, _row, issues} -> issues
    end)
  end

  defp csv(lines), do: {:string, Enum.join(lines, "\n") <> "\n"}

  defp describe_issue(fields), do: Issue.describe(struct!(Issue, fields))

  describe "a unique column" do
    test "each later row holding a value seen before is an issue naming the first line" do
      rows = [
        row(%{"account" => "A-1"}),
        row(%{"account" => "A-2"}),
        row(%{"account" => "A-1"}),
        row(%{"account" => "A-1"})
      ]

      assert [
               %{line: 3, column: "account", rule: :unique, first_line: 1},
               %{line: 4, column: "account", rule: :unique, first_line: 1}
             ] = issues(rows, accounts())
    end

    test "values all different give no issues" do
      rows = Enum.map(1..5, &row(%{"account" => "A-#{&1}"}))

      assert issues(rows, accounts()) == []
    end

    test "blank cells are skipped" do
      rows = [row(%{"account" => ""}), row(%{"account" => nil}), row(%{"account" => ""})]

      assert issues(rows, accounts()) == []
    end

    test "a cell failing another rule of its column is that issue only and is not remembered" do
      shape = shape(columns: %{"account" => [~r/^A-\d+$/, :unique]})
      rows = [row(%{"account" => "bad"}), row(%{"account" => "bad"}), row(%{"account" => "A-1"})]

      assert [
               %{line: 1, column: "account", rule: %Regex{}},
               %{line: 2, column: "account", rule: %Regex{}}
             ] = issues(rows, shape)
    end

    test "values are compared as read" do
      rows = [
        row(%{"account" => "A-1"}),
        row(%{"account" => "a-1"}),
        row(%{"account" => " A-1"}),
        row(%{"account" => 1}),
        row(%{"account" => "1"})
      ]

      assert issues(rows, accounts()) == []
    end

    test "two unique columns are tracked apart" do
      shape = shape(columns: %{"account" => [:unique], "order_no" => [:unique]})

      rows = [
        row(%{"account" => "A-1", "order_no" => "SO-1"}),
        row(%{"account" => "SO-1", "order_no" => "A-1"}),
        row(%{"account" => "A-2", "order_no" => "SO-1"})
      ]

      assert [%{line: 3, column: "order_no", first_line: 1}] = issues(rows, shape)
    end

    test "the value shows with values: true, the record with identify_by:" do
      rows = [
        row(%{"account" => "A-1", "order_no" => "SO-1"}),
        row(%{"account" => "A-1", "order_no" => "SO-2"})
      ]

      assert [%{value: nil}] = issues(rows, accounts())

      assert [%{value: "A-1", record: %{"order_no" => "SO-2"}}] =
               issues(rows, accounts(), values: true, identify_by: "order_no")
    end
  end

  describe "a unique combination" do
    test "a pair seen before is one issue for the row, with no column" do
      rows = [
        row(%{"order_no" => "SO-7", "line_no" => "1"}),
        row(%{"order_no" => "SO-7", "line_no" => "2"}),
        row(%{"order_no" => "SO-8", "line_no" => "1"}),
        row(%{"order_no" => "SO-7", "line_no" => "2"})
      ]

      assert [%{line: 4, column: nil, rule: {:unique, ["order_no", "line_no"]}, first_line: 2}] =
               issues(rows, lines())
    end

    test "a row with any of the columns blank is skipped" do
      rows = [
        row(%{"order_no" => "SO-7", "line_no" => ""}),
        row(%{"order_no" => "SO-7", "line_no" => ""}),
        row(%{"order_no" => nil, "line_no" => "1"}),
        row(%{"order_no" => nil, "line_no" => "1"})
      ]

      assert issues(rows, lines()) == []
    end

    test "a column and a combination are tracked apart" do
      shape = shape(columns: %{"account" => [:unique]}, unique: [["order_no", "line_no"]])

      rows = [
        row(%{"account" => "A-1", "order_no" => "SO-7", "line_no" => "1"}),
        row(%{"account" => "A-1", "order_no" => "SO-7", "line_no" => "1"})
      ]

      assert [
               %{line: 2, column: "account", rule: :unique},
               %{line: 2, column: nil, rule: {:unique, ["order_no", "line_no"]}}
             ] = Enum.sort_by(issues(rows, shape), &is_nil(&1.column))
    end
  end

  describe "the shape" do
    test "unique is kept apart from the cell rules, a shape without it has none" do
      shape =
        shape(columns: %{"account" => [:required, :unique]}, unique: [["order_no", "line_no"]])

      assert shape.validation.columns["account"] == [:required]
      assert Enum.sort(shape.validation.unique) == [["account"], ["order_no", "line_no"]]
      assert shape(columns: %{"account" => [:required]}).validation.unique == []
    end

    test "a combination must name columns of the shape, at least two" do
      for unique <- [[["order_no", "colour"]], [["order_no"]], [[]], ["order_no"], :order_no] do
        assert_raise ArgumentError, ~r/unique/, fn -> shape(unique: unique) end
      end
    end

    test "yaml shapes take unique on a column and as combinations" do
      map = %{
        "name" => "orders",
        "header" => %{
          "columns" => %{
            "account" => ["account"],
            "order_no" => ["order no"],
            "line_no" => ["line no"]
          }
        },
        "validation" => %{
          "columns" => %{"account" => ["required", "unique"]},
          "unique" => [["order_no", "line_no"]]
        }
      }

      assert {:ok, shape} = Shape.from_map(map)
      assert shape.validation.columns["account"] == [:required]
      assert Enum.sort(shape.validation.unique) == [["account"], ["order_no", "line_no"]]
    end

    test "yaml unique that is not a list of column lists is an error naming where" do
      map = %{
        "name" => "orders",
        "header" => %{"columns" => %{"order_no" => ["order no"]}},
        "validation" => %{"unique" => "order_no"}
      }

      assert {:error, {:invalid_value, {"validation.unique", "order_no"}}} = Shape.from_map(map)
    end
  end

  describe "max_tracked:" do
    test "past the limit one issue for the check, then no more from it, others carry on" do
      shape = shape(columns: %{"account" => [:unique], "order_no" => [:unique]})

      rows = [
        row(%{"account" => "A-1", "order_no" => "SO-1"}),
        row(%{"account" => "A-2", "order_no" => "SO-1"}),
        row(%{"account" => "A-3", "order_no" => "SO-2"}),
        row(%{"account" => "A-1", "order_no" => "SO-1"})
      ]

      assert [
               %{line: 2, column: "order_no", rule: :unique, first_line: 1},
               %{line: 3, column: "account", rule: {:max_tracked, :unique}},
               %{line: 4, column: "order_no", rule: :unique, first_line: 1}
             ] = Enum.sort_by(issues(rows, shape, max_tracked: 2), & &1.line)
    end

    test "a combination past the limit names the combination" do
      rows = Enum.map(1..3, &row(%{"order_no" => "SO-#{&1}", "line_no" => "1"}))

      assert [%{line: 3, column: nil, rule: {:max_tracked, {:unique, ["order_no", "line_no"]}}}] =
               issues(rows, lines(), max_tracked: 2)
    end

    test "max_tracked is checked" do
      for max_tracked <- [0, -1, "10", 1.5] do
        assert_raise ArgumentError, ~r/max_tracked must be a positive integer/, fn ->
          Validate.rows([], accounts(), max_tracked: max_tracked)
        end
      end
    end
  end

  describe "through the readers" do
    test "csv lines are source lines, first lines too" do
      source =
        csv([
          "ORDERS EXPORT,,,",
          "Account,Order No,Line No,Qty",
          "A-1,SO-7,1,1",
          "A-2,SO-7,2,1",
          "A-1,SO-7,2,1"
        ])

      shape = shape(columns: %{"account" => [:unique]}, unique: [["order_no", "line_no"]])

      assert {:ok, %Validate.Result{valid: false, issues: issues}} = CSV.validate(source, shape)

      assert [
               %{line: 5, column: "account", rule: :unique, first_line: 3},
               %{line: 5, column: nil, rule: {:unique, ["order_no", "line_no"]}, first_line: 4}
             ] = Enum.sort_by(issues, &is_nil(&1.column))
    end

    test "a shape with document rules checks unique on the loaded rows" do
      shape =
        shape(
          columns: %{"account" => [:unique]},
          document: [{:has_rows, fn %{rows: rows} -> rows != [] end}]
        )

      source = csv(["Account,Order No,Line No,Qty", "A-1,SO-7,1,1", "A-1,SO-7,2,1"])

      assert {:ok, %Validate.Result{issues: [%{line: 3, rule: :unique, first_line: 2}]}} =
               CSV.validate(source, shape)
    end

    test "max_tracked: reaches validate through the reader" do
      source = csv(["Account,Order No,Line No,Qty", "A-1,SO-7,1,1", "A-2,SO-7,2,1"])

      assert {:ok, %Validate.Result{issues: [%{rule: {:max_tracked, :unique}}]}} =
               CSV.validate(source, accounts(), max_tracked: 1)
    end
  end

  describe "Issue.describe/1" do
    test "a unique column" do
      assert describe_issue(line: 9, column: "account", rule: :unique, first_line: 3) ==
               "line 9, account: must be unique, first on line 3"
    end

    test "a unique combination with its record" do
      assert describe_issue(
               line: 9,
               rule: {:unique, ["order_no", "line_no"]},
               first_line: 3,
               record: %{"order_no" => "SO-7", "line_no" => "2"}
             ) ==
               "line 9 (line_no 2, order_no SO-7): order_no and line_no must be unique together, first on line 3"
    end

    test "the limit" do
      assert describe_issue(line: 4, column: "account", rule: {:max_tracked, :unique}) ==
               "line 4, account: unique not checked past this point (more values matched than max_tracked)"
    end
  end

  describe "Validate.Result.to_map/1" do
    test "carries the first line" do
      result = %Validate.Result{
        valid: false,
        rows: 2,
        issues: [struct!(Issue, line: 2, column: "account", rule: :unique, first_line: 1)]
      }

      assert %{issues: [%{rule: ":unique", first_line: 1}]} = Validate.Result.to_map(result)
    end
  end
end
