defmodule Refract.E2E.AwsTest do
  use ExUnit.Case, async: true

  @moduletag :e2e
  @moduletag timeout: 5_000

  alias Refract.CSV
  alias Refract.Golden
  alias Refract.Rows

  @account "987654321"

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
end
