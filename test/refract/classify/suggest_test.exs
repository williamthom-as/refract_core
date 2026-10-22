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

  describe "suggest/3 names" do
    test "a column its aliases already match is suggested as an alias" do
      mapping =
        suggest([["account_id", "Client Name", "cost", "usage_date"], ["1", "a", "2", "x"]])

      assert mapping.header_row == 1

      assert %{cell: "Client Name", index: 1, alias: "client name", via: :alias} =
               mapping.columns["customer"]

      assert mapping.columns["cost"].score == 1.0
      assert mapping.unmapped == []
      assert mapping.extra == []
    end

    test "names that differ only in case and separators are normalised" do
      mapping = suggest([["accountId", "USAGE-DATE"]])

      assert %{cell: "accountId", index: 0, via: :normalised} = mapping.columns["account_id"]
      assert %{cell: "USAGE-DATE", index: 1, via: :normalised} = mapping.columns["usage_date"]
    end

    test "a header holding every word of a name or alias is suggested by its words" do
      mapping = suggest([["Total Cost", "Client Full Name"]])

      assert %{cell: "Total Cost", alias: "cost", via: :tokens} = mapping.columns["cost"]

      assert %{cell: "Client Full Name", alias: "client name", via: :tokens} =
               mapping.columns["customer"]
    end

    test "a misspelt name is suggested as fuzzy" do
      assert %{cell: "Custmer", via: :fuzzy} =
               Classify.suggest([["Custmer"]], shape(%{"customer" => ["customer"]})).columns[
                 "customer"
               ]
    end

    test "a different word that only looks alike is not suggested" do
      mapping =
        Classify.suggest(
          [["Amount", "Consumer"]],
          shape(%{"account" => ["account"], "customer" => ["customer"]})
        )

      assert mapping.header_row == nil
      assert mapping.columns == %{}
      assert mapping.unmapped == ["account", "customer"]
    end

    test "an alias scores above a normalised name, which scores above words or a misspelling" do
      mapping = suggest([["Client Name", "accountId", "Total Cost", "Usage Dte"]])

      alias_score = mapping.columns["customer"].score
      normalised = mapping.columns["account_id"].score

      assert alias_score > normalised
      assert normalised > mapping.columns["cost"].score
      assert normalised > mapping.columns["usage_date"].score
    end
  end

  describe "suggest/3 one to one" do
    test "a cell goes to the column it fits best, the other column stays unmapped" do
      mapping =
        Classify.suggest(
          [["Total Cost"]],
          shape(%{"cost" => ["cost"], "total_cost" => ["total_cost"]})
        )

      assert %{cell: "Total Cost", via: :normalised} = mapping.columns["total_cost"]
      refute Map.has_key?(mapping.columns, "cost")
      assert mapping.unmapped == ["cost"]
    end

    test "a column takes the cell it fits best, the rest are extra" do
      mapping = suggest([["Costs", "Cost"]])

      assert mapping.columns["cost"].cell == "Cost"
      assert mapping.extra == ["Costs"]
    end

    test "cells nothing fits are extra in line order, columns nothing fits are unmapped" do
      mapping = suggest([["Region", "account_id", "Notes"]])

      assert mapping.extra == ["Region", "Notes"]
      assert mapping.unmapped == ["cost", "customer", "usage_date"]
    end
  end

  describe "suggest/3 header line" do
    test "the header is found below title lines" do
      mapping = suggest([["Usage report"], [], ["accountId", "Total Cost"], ["1", "2"]])

      assert mapping.header_row == 3
      assert mapping.columns["account_id"].index == 0
    end

    test "header_row: takes that line" do
      mapping = suggest([["cost"], ["x"], ["Total Cost"]], header_row: 3)

      assert mapping.header_row == 3
      assert mapping.columns["cost"].cell == "Total Cost"
    end

    test "only the first within: lines are searched" do
      mapping = suggest([["a"], ["b"], ["accountId"]], within: 2)

      assert mapping.header_row == nil
      assert mapping.columns == %{}
    end

    test "no line any column fits gives no header and every column unmapped" do
      mapping = suggest([["a", "b"], ["1", "2"]])

      assert mapping.header_row == nil
      assert mapping.columns == %{}
      assert mapping.unmapped == ["account_id", "cost", "customer", "usage_date"]
      assert mapping.extra == []
    end
  end

  describe "suggest/3 shape and options" do
    test "row values never appear in the mapping" do
      mapping = suggest([["accountId", "Total Cost"], ["secret-account", "secret-cost"]])

      refute inspect(mapping) =~ "secret"
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

      assert {:ok, mapping} = CSV.suggest({:string, csv}, usage())
      assert mapping.header_row == 3
      assert mapping.columns["cost"].via == :tokens
    end

    test "a source that cannot be read is an error" do
      assert {:error, :enoent} = CSV.suggest("missing.csv", usage())
    end
  end
end
