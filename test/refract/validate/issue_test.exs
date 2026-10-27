defmodule Refract.Validate.IssueTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 10_000

  alias Refract.CSV
  alias Refract.Shape
  alias Refract.Table
  alias Refract.Validate.Issue

  defp describe_issue(fields), do: Issue.describe(struct!(Issue, fields))

  describe "where" do
    test "line and column" do
      assert describe_issue(line: 3, column: "account", rule: :required) ==
               "line 3, account: is required"
    end

    test "line and field" do
      assert describe_issue(line: 2, field: "opened", rule: :date) ==
               "line 2, field opened: must be a date"
    end

    test "field only when it was not found" do
      assert describe_issue(field: "issued_on", rule: :required) == "field issued_on: is required"
    end

    test "line only for a row rule" do
      assert describe_issue(line: 5, rule: :totals_match) == "line 5: fails totals_match"
    end

    test "nothing for a document rule" do
      assert describe_issue(rule: :totals_balance) == "fails totals_balance"
    end

    test "the value when kept" do
      assert describe_issue(line: 4, column: "amount", rule: :number, value: "n/a") ==
               ~s(line 4, amount: must be a number, got "n/a")
    end
  end

  describe "rules" do
    test "types" do
      assert describe_issue(rule: :integer) == "must be an integer"
      assert describe_issue(rule: :number) == "must be a number"
      assert describe_issue(rule: :date) == "must be a date"
      assert describe_issue(rule: :datetime) == "must be a datetime"
    end

    test "date formats" do
      assert describe_issue(rule: {:date, [:dmy, :iso]}) == "must be a date (dmy, iso)"

      assert describe_issue(rule: {:datetime, ["dd.MM.yyyy"]}) ==
               "must be a datetime (dd.MM.yyyy)"
    end

    test "bounds and lists" do
      assert describe_issue(rule: {:min, 0}) == "must be at least 0"
      assert describe_issue(rule: {:max, ~D[2026-12-31]}) == "must be at most 2026-12-31"
      assert describe_issue(rule: {:in, ["AUD", "NZD"]}) == "must be one of AUD, NZD"
    end

    test "regex" do
      assert describe_issue(rule: ~r/^\d+$/) == "must match ~r/^\\d+$/"
    end

    test "a missing column" do
      assert describe_issue(line: 1, column: "branch", rule: :column_missing) ==
               "line 1, branch: column is missing"
    end

    test "recognition reads as its rule" do
      assert describe_issue(line: 6, column: "date", rule: {:recognition, :date}) ==
               "line 6, date: must be a date"
    end

    test "validator modules by name" do
      assert describe_issue(rule: Acme.Abn) == "fails Acme.Abn"
      assert describe_issue(rule: {Acme.Abn, strict: true}) == "fails Acme.Abn"
    end
  end

  test "describes the issues validate finds" do
    shape =
      Shape.new(
        name: "ledger",
        spec: Table.spec(header: [columns: %{"account" => ["account"], "amount" => ["amount"]}]),
        validation: [columns: %{"account" => [:required], "amount" => [:number]}]
      )

    source = {:string, "Account,Amount\n,1.00\nA-100,n/a\n"}

    assert {:ok, %{issues: issues}} = CSV.validate(source, shape, values: true)

    assert Enum.map(issues, &Issue.describe/1) == [
             "line 2, account: is required",
             ~s(line 3, amount: must be a number, got "n/a")
           ]
  end
end
