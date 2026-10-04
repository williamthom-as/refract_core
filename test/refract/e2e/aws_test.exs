defmodule Refract.E2E.AwsTest do
  use ExUnit.Case, async: true

  @moduletag :e2e
  @moduletag :tmp_dir
  @moduletag timeout: 5_000

  alias Refract.CSV
  alias Refract.Golden
  alias Refract.Privacy.Gen
  alias Refract.Privacy.Keyring
  alias Refract.Rows

  @account "987654321"

  @keyring Keyring.new!(keys: %{1 => :binary.copy(<<1>>, 32)})

  @columns ~w(
    bill/BillingEntity bill/PayerAccountId bill/BillingPeriodStartDate bill/BillingPeriodEndDate
    lineItem/UsageAccountId lineItem/LineItemType lineItem/UsageStartDate lineItem/UsageEndDate
    lineItem/ProductCode lineItem/UsageType lineItem/ResourceId lineItem/UsageAmount
    lineItem/CurrencyCode
  )

  defp rot13(value) do
    value
    |> String.replace(~r/[^a-zA-Z0-9]/, "")
    |> String.to_charlist()
    |> Enum.map(fn
      char when char in ?a..?m or char in ?A..?M -> char + 13
      char when char in ?n..?z or char in ?N..?Z -> char - 13
      char -> char
    end)
    |> List.to_string()
  end

  defp resource_id(value) do
    cond do
      value =~ ~r/^i-/ -> Regex.replace(~r/^i-(.*)/, value, fn _, _id -> "i-" <> rot13(value) end)
      value =~ "1234567890" -> String.replace(value, "1234567890", @account)
      true -> rot13(value)
    end
  end

  describe "resource id rules as a plain function" do
    test "first matching rule wins, else falls back, blanks skipped" do
      {:ok, input} = CSV.stream(Golden.path("aws", "input.csv"))
      {:ok, expected} = CSV.stream(Golden.path("aws", "expected.csv"))

      ids =
        input
        |> Rows.update("lineItem/ResourceId", &resource_id/1, skip_blank: true)
        |> Enum.map(& &1["lineItem/ResourceId"])

      assert ids == Enum.map(expected, & &1["lineItem/ResourceId"])
    end
  end

  test "keeps the billing columns, swaps accounts and anonymises resource ids", %{tmp_dir: dir} do
    out = Path.join(dir, "aws.csv")

    assert {:ok, rows} = CSV.stream(Golden.path("aws", "input.csv"))

    assert :ok =
             rows
             |> Rows.take(@columns)
             |> Rows.update("bill/PayerAccountId", fn _ -> @account end)
             |> Rows.update(
               "lineItem/UsageAccountId",
               &Gen.digits(&1, length: 10, domain: :aws_account, keyring: @keyring)
             )
             |> Rows.update("lineItem/ResourceId", &resource_id/1, skip_blank: true)
             |> CSV.write(out, header: @columns)

    assert File.read!(out) == Golden.expected("aws")
  end
end
