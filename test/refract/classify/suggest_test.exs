defmodule Refract.Classify.SuggestTest.Usage do
  use Refract.Shape

  @impl Refract.Shape
  def shape, do: Refract.Classify.SuggestTest.usage()
end

defmodule Refract.Classify.SuggestTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 10_000

  alias Refract.Classify
  alias Refract.Classify.SuggestTest.Usage
  alias Refract.CSV
  alias Refract.Shape
  alias Refract.Table

  def usage do
    Shape.new(
      name: "usage",
      spec:
        Table.spec(
          header: [
            columns: %{
              "account_id" => ["account_id"],
              "customer" => ["client name"],
              "cost" => ["cost"],
              "usage_date" => ["usage_date"]
            }
          ]
        )
    )
  end

  defp shape(columns), do: Shape.new(name: "other", spec: Table.spec(header: [columns: columns]))

  defp suggest(lines, opts \\ []), do: Classify.suggest(lines, usage(), opts)

  defp unmapped(report), do: for({column, %{passed: false}} <- report.columns, do: column)

  defp mapped(report), do: for({column, %{passed: true}} <- report.columns, do: column)

  describe "suggest/3 names" do
    test "a column its aliases already match is suggested as an alias" do
      report =
        suggest([["account_id", "Client Name", "cost", "usage_date"], ["1", "a", "2", "x"]])

      assert report.check == :header
      assert report.row == 1

      assert %{passed: true, cell: "Client Name", index: 1, rule: "client name", via: :alias} =
               report.columns["customer"]

      assert report.columns["cost"].score == 1.0
      assert unmapped(report) == []
      assert report.extra == []
    end

    test "names that differ only in case and separators are normalised" do
      report = suggest([["accountId", "USAGE-DATE"]])

      assert %{cell: "accountId", index: 0, via: :normalised} = report.columns["account_id"]
      assert %{cell: "USAGE-DATE", index: 1, via: :normalised} = report.columns["usage_date"]
    end

    test "a header holding every word of a name or alias is suggested by its words" do
      report = suggest([["Total Cost", "Client Full Name"]])

      assert %{cell: "Total Cost", rule: "cost", via: :tokens} = report.columns["cost"]

      assert %{cell: "Client Full Name", rule: "client name", via: :tokens} =
               report.columns["customer"]
    end

    test "a misspelt name is suggested as fuzzy" do
      report = Classify.suggest([["Custmer"]], shape(%{"customer" => ["customer"]}))

      assert %{cell: "Custmer", via: :fuzzy} = report.columns["customer"]
    end

    test "a different word that only looks alike is not suggested" do
      report =
        Classify.suggest(
          [["Amount", "Consumer"]],
          shape(%{"account" => ["account"], "customer" => ["customer"]})
        )

      assert report.row == nil
      assert mapped(report) == []
      assert Enum.sort(unmapped(report)) == ["account", "customer"]
    end

    test "an alias scores above a normalised name, which scores above words or a misspelling" do
      report = suggest([["Client Name", "accountId", "Total Cost", "Usage Dte"]])

      alias_score = report.columns["customer"].score
      normalised = report.columns["account_id"].score

      assert alias_score > normalised
      assert normalised > report.columns["cost"].score
      assert normalised > report.columns["usage_date"].score
    end
  end

  describe "suggest/3 one to one" do
    test "a cell goes to the column it fits best, the other column stays unmapped" do
      report =
        Classify.suggest(
          [["Total Cost"]],
          shape(%{"cost" => ["cost"], "total_cost" => ["total_cost"]})
        )

      assert %{passed: true, cell: "Total Cost", via: :normalised} = report.columns["total_cost"]
      assert %{passed: false, index: nil} = report.columns["cost"]
    end

    test "a column takes the cell it fits best, the rest are extra" do
      report = suggest([["Costs", "Cost"]])

      assert report.columns["cost"].cell == "Cost"
      assert report.extra == [{0, "Costs"}]
    end

    test "cells nothing fits are extra in line order, columns nothing fits are unmapped" do
      report = suggest([["Region", "account_id", "Notes"]])

      assert report.extra == [{0, "Region"}, {2, "Notes"}]
      assert Enum.sort(unmapped(report)) == ["cost", "customer", "usage_date"]
    end
  end

  describe "suggest/3 header rules" do
    test "the header passes when the suggestions cover the shape" do
      assert suggest([["accountId", "Client Name", "Total Cost", "usage_date"]]).passed
    end

    test "the header fails when they do not, saying how many columns it found" do
      report = suggest([["accountId", "Total Cost"]])

      refute report.passed

      assert %{passed: false, expected: 4, actual: 2} =
               Enum.find(report.rules, &(&1.rule == :min_matches))
    end
  end

  describe "suggest/3 header line" do
    test "the header is found below title lines" do
      report = suggest([["Usage report"], [], ["accountId", "Total Cost"], ["1", "2"]])

      assert report.row == 3
      assert report.columns["account_id"].index == 0
    end

    test "header_row: takes that line" do
      report = suggest([["cost"], ["x"], ["Total Cost"]], header_row: 3)

      assert report.row == 3
      assert report.columns["cost"].cell == "Total Cost"
    end

    test "only the first within: lines are searched" do
      report = suggest([["a"], ["b"], ["accountId"]], within: 2)

      assert report.row == nil
      assert mapped(report) == []
    end

    test "no line any column fits gives no header and every column unmapped" do
      report = suggest([["a", "b"], ["1", "2"]])

      assert report.row == nil
      refute report.passed
      assert Enum.sort(unmapped(report)) == ["account_id", "cost", "customer", "usage_date"]
      assert report.extra == []
    end
  end

  describe "suggest/3 shape and options" do
    test "row values never appear in the report" do
      report = suggest([["accountId", "Total Cost"], ["secret-account", "secret-cost"]])

      refute inspect(report) =~ "secret"
    end

    test "the shape can be a module" do
      assert Classify.suggest([["accountId"]], Usage).columns["account_id"].via == :normalised
    end

    test "bad options raise" do
      for opts <- [[within: 0], [header_row: 0], [header_row: "3"], [colour: :blue]] do
        assert_raise ArgumentError, fn -> suggest([["accountId"]], opts) end
      end
    end
  end

  describe "reader suggest/3" do
    test "a reader suggests from a source" do
      csv = "Usage report\n\naccountId,Total Cost\n1,2\n"

      assert {:ok, report} = CSV.suggest({:string, csv}, usage())
      assert report.row == 3
      assert report.columns["cost"].via == :tokens
    end

    test "a source that cannot be read is an error" do
      assert {:error, :enoent} = CSV.suggest("missing.csv", usage())
    end
  end
end
