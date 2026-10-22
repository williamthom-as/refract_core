defmodule Refract.E2E.OnboardSourceTest do
  use ExUnit.Case, async: true

  @moduletag :e2e
  @moduletag timeout: 10_000

  alias Refract.Classify.Result
  alias Refract.CSV
  alias Refract.Shape
  alias Refract.Table

  @columns %{
    "account_id" => ["account_id"],
    "customer" => ["customer"],
    "cost" => ["cost"],
    "usage_date" => ["usage_date"]
  }

  @rules %{"account_id" => ~r/^\d{12}$/, "cost" => :number, "usage_date" => :date}

  @known {:string,
          "account_id,customer,cost,usage_date\n" <>
            "123456789012,alice,1.50,2026-10-01\n" <>
            "123456789013,bob,2.25,2026-10-02\n"}

  @new {:string,
        "Billing export\n\n" <>
          "Customer Name,Acct Number,Date Used,Amount\n" <>
          "alice,123456789012,2026-10-03,4.00\n" <>
          "bob,123456789013,2026-10-04,0.75\n"}

  defp billing(columns),
    do:
      Shape.new(
        name: "billing",
        spec: Table.spec(header: [columns: columns], row: [match: @rules])
      )

  defp with_suggestions(columns, report) do
    Map.new(columns, fn {column, aliases} ->
      {column, aliases ++ suggested(report.columns[column])}
    end)
  end

  defp suggested(%{passed: true, cell: cell}), do: [cell]
  defp suggested(_column), do: []

  test "a new source is suggested, its aliases added, then it classifies and locates" do
    shape = billing(@columns)

    assert {:ok, %Result{verdict: :match}} = CSV.classify(@known, [shape])

    assert {:ok, %Result{verdict: :unknown, shape: nil, candidates: [candidate]}} =
             CSV.classify(@new, [shape])

    assert {:ok, report} = CSV.suggest(@new, candidate.shape)

    assert report.row == 3
    assert report.passed

    assert %{
             "customer" => %{cell: "Customer Name", via: :tokens},
             "account_id" => %{cell: "Acct Number", via: :values, rows: {2, 2}},
             "usage_date" => %{cell: "Date Used", via: :values, rows: {2, 2}},
             "cost" => %{cell: "Amount", via: :values, rows: {2, 2}}
           } = report.columns

    onboarded = billing(with_suggestions(@columns, report))

    assert {:ok, %Result{verdict: :match}} = CSV.classify(@new, [onboarded])
    assert {:ok, %Result{verdict: :match}} = CSV.classify(@known, [onboarded])

    assert {:ok, table} = CSV.locate(@new, onboarded.spec, header_row: report.row)

    assert Enum.to_list(table.rows) == [
             %{
               "account_id" => "123456789012",
               "customer" => "alice",
               "cost" => "4.00",
               "usage_date" => "2026-10-03"
             },
             %{
               "account_id" => "123456789013",
               "customer" => "bob",
               "cost" => "0.75",
               "usage_date" => "2026-10-04"
             }
           ]
  end

  test "a 12 digit id passing both a number and an id rule goes to one column only" do
    assert {:ok, report} = CSV.suggest(@new, billing(@columns))

    assert report.columns["account_id"].index == 1
    assert report.columns["cost"].index == 3
  end
end
