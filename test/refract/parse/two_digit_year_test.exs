defmodule Refract.Parse.TwoDigitYearTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  alias Refract.CSV
  alias Refract.Parse
  alias Refract.Shape
  alias Refract.Table

  defp date(value, formats), do: Parse.date(value, formats: formats)

  test "20yy reads two year digits in the 2000s" do
    assert date("08/01/25", ["dd/MM/20yy"]) == {:ok, ~D[2025-01-08]}
    assert date("8/1/99", ["d/M/20yy"]) == {:ok, ~D[2099-01-08]}
  end

  test "19yy reads two year digits in the 1900s" do
    assert date("08.01.65", ["dd.MM.19yy"]) == {:ok, ~D[1965-01-08]}
    assert date("08.01.25", ["dd.MM.19yy"]) == {:ok, ~D[1925-01-08]}
  end

  test "the century may lead the pattern" do
    assert date("25-01-08", ["20yy-MM-dd"]) == {:ok, ~D[2025-01-08]}
  end

  test "20yy needs exactly two digits" do
    for value <- ["08/01/5", "08/01/2025", "08/01/2a"] do
      assert {:error, _} = date(value, ["dd/MM/20yy"])
    end
  end

  test "yy alone raises, asking for the century" do
    assert_raise ArgumentError, ~r/20yy or 19yy/, fn -> date("08/01/25", ["dd/MM/yy"]) end
    assert_raise ArgumentError, ~r/20yy or 19yy/, fn -> date("0108yy", ["MMddyy"]) end
  end

  test "named formats still need four year digits" do
    assert {:error, _} = date("08/01/25", [:dmy])
  end

  test "a datetime with a century pattern" do
    assert Parse.datetime("08/01/25 09:30", formats: ["dd/MM/20yy"]) ==
             {:ok, ~N[2025-01-08 09:30:00]}
  end

  test "a date rule with a century pattern validates" do
    shape =
      Shape.new(
        name: "statement",
        spec: Table.spec(header: [columns: %{"date" => ["date"]}]),
        validation: [columns: %{"date" => [{:date, ["dd/MM/20yy"]}]}]
      )

    assert {:ok, %{valid: true}} = CSV.validate({:string, "Date\n08/01/25\n31/12/24\n"}, shape)
    assert {:ok, %{valid: false}} = CSV.validate({:string, "Date\n31/02/25\n"}, shape)
  end

  test "a shape map takes a century pattern" do
    map = %{
      "name" => "statement",
      "header" => %{"columns" => %{"date" => ["date"]}},
      "validation" => %{"columns" => %{"date" => [%{"date" => ["dd/MM/20yy"]}]}}
    }

    assert {:ok, shape} = Shape.from_map(map)
    assert shape.validation.columns["date"] == [{:date, ["dd/MM/20yy"]}]
  end
end
