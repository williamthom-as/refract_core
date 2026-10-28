defmodule Refract.Classify.DriftTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 10_000

  alias Refract.Classify
  alias Refract.CSV
  alias Refract.Shape
  alias Refract.Table

  @columns %{
    "account_id" => ["account_id"],
    "customer" => ["customer"],
    "cost" => ["total cost", "cost"],
    "region" => ["region"]
  }

  defp billing(header_opts \\ [], name \\ "billing") do
    Shape.new(
      name: name,
      spec: Table.spec(header: Keyword.merge([columns: @columns], header_opts))
    )
  end

  defp classify(lines, shapes \\ [billing()]), do: Classify.lines(lines, shapes)

  describe "drift on classify results" do
    test "a match with exactly the shape's columns has no drift" do
      result = classify([["account_id", "customer", "cost", "region"], ["1", "a", "2", "x"]])

      assert result.verdict == :match
      assert result.drift.missing == []
      assert result.drift.extra == []
      assert result.drift.others == %{}
    end

    test "header cells no column claimed are extra" do
      result = classify([["account_id", "customer", "Notes", "cost", "", "region"]])

      assert result.verdict == :match
      assert result.drift.extra == [{2, "Notes"}]
    end

    test "optional columns a match lacks are missing" do
      result = classify([["account_id", "customer", "cost"]], [billing(min_matches: 3)])

      assert result.verdict == :match
      assert result.drift.missing == ["region"]
    end

    test "a column more than one cell matched lists the other cells" do
      result = classify([["Cost", "account_id", "customer", "Total Cost", "region"]])

      assert result.verdict == :match
      assert result.drift.others == %{"cost" => [{0, "Cost"}]}
      assert result.drift.extra == []
    end

    test "an unknown result has drift against its closest shape" do
      result = classify([["account_id", "customer", "cost", "Area"]])

      assert result.verdict == :unknown
      assert result.shape.name == "billing"
      assert result.drift.missing == ["region"]
      assert result.drift.extra == [{3, "Area"}]
    end

    test "no closest shape, no drift" do
      result = classify([["a", "b"], ["1", "2"]])

      assert result.shape == nil
      assert result.drift == nil
    end

    test "an ambiguous result has no drift" do
      result =
        classify([["account_id", "customer", "cost", "region"]], [
          billing([], "billing"),
          billing([], "billing_copy")
        ])

      assert result.verdict == :ambiguous
      assert result.drift == nil
    end

    test "drift names header cells only, never row values" do
      result = classify([["account_id", "customer", "cost", "region"], ["secret", "a", "2", "x"]])

      refute inspect(result.drift) =~ "secret"
    end

    test "a reader classify carries drift" do
      csv = "account_id,customer,cost,region,Notes\n1,a,2,x,y\n"

      assert {:ok, result} = CSV.classify({:string, csv}, [billing()])
      assert result.drift.extra == [{4, "Notes"}]
    end
  end

  describe "ignore" do
    @cost_centres ~r/^cost centre \d+$/i

    test "ignored cells are not extra, the rest still are" do
      line = [
        "account_id",
        "customer",
        "cost",
        "region",
        "Cost Centre 101",
        "Cost Centre 205",
        "Notes",
        "Area"
      ]

      result = classify([line], [billing(ignore: [@cost_centres, "notes"])])

      assert result.verdict == :match
      assert result.drift.extra == [{7, "Area"}]
    end

    test "a plain name matches like an alias, trimmed and in any case" do
      result =
        classify([["account_id", "customer", "cost", "region", " NOTES "]], [
          billing(ignore: ["notes"])
        ])

      assert result.drift.extra == []
    end

    test "a cell a column matches is still that column" do
      result =
        classify([["account_id", "customer", "cost", "region"]], [billing(ignore: ["cost"])])

      assert result.verdict == :match
      assert result.drift.missing == []
    end

    test "the verdict and score do not change" do
      line = ["account_id", "customer", "cost", "region", "Cost Centre 101"]

      plain = classify([line, ["1", "a", "2", "x", "3"]])
      ignoring = classify([line, ["1", "a", "2", "x", "3"]], [billing(ignore: [@cost_centres])])

      assert {plain.verdict, hd(plain.candidates).score} ==
               {ignoring.verdict, hd(ignoring.candidates).score}
    end

    test "suggest leaves ignored cells out of extra" do
      line = ["account_id", "customer", "cost", "region", "Cost Centre 101", "Notes"]

      report = Classify.suggest([line], billing(ignore: [@cost_centres]))

      assert report.extra == [{5, "Notes"}]
    end

    test "ignore is a list of names and regexes" do
      assert_raise ArgumentError, ~r/ignore/, fn -> billing(ignore: "notes") end
      assert_raise ArgumentError, ~r/ignore/, fn -> billing(ignore: [1]) end
    end

    test "a shape map takes ignore, names and patterns" do
      assert {:ok, shape} =
               Shape.from_map(%{
                 "name" => "billing",
                 "header" => %{
                   "columns" => %{"account_id" => ["account_id"]},
                   "ignore" => ["notes", "/^cost centre \\d+$/i"]
                 }
               })

      result = Classify.lines([["account_id", "Notes", "Cost Centre 7", "Area"]], [shape])

      assert result.drift.extra == [{3, "Area"}]
    end

    test "a bad ignore in a shape map is an invalid value" do
      assert {:error, {:invalid_value, {"header.ignore", 1}}} =
               Shape.from_map(%{
                 "name" => "billing",
                 "header" => %{"columns" => %{"account_id" => ["account_id"]}, "ignore" => [1]}
               })
    end
  end
end
