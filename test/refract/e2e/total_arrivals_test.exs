defmodule Refract.E2E.TotalArrivalsTest do
  use ExUnit.Case, async: true

  @moduletag :e2e
  @moduletag :tmp_dir
  @moduletag timeout: 10_000

  alias Refract.CSV
  alias Refract.Golden
  alias Refract.Parse
  alias Refract.Rows

  test "renames, converts millions to units, derives difference and year, stops at the notes",
       %{tmp_dir: dir} do
    out = Path.join(dir, "travel_data.csv")

    to_units = fn value ->
      value |> Parse.number!() |> Decimal.mult(1_000_000) |> Decimal.to_integer()
    end

    assert {:ok, rows} = CSV.stream(Golden.path("total_arrivals", "input.csv"), skip: 1)

    assert :ok =
             rows
             |> Rows.until(&Rows.blank?/1)
             |> Rows.rename(%{
               "col_0" => "date",
               "Arrivals (M)" => "arrivals",
               "Departures (M)" => "departures"
             })
             |> Rows.update(["arrivals", "departures"], to_units)
             |> Rows.put("difference", &(&1["arrivals"] - &1["departures"]))
             |> Rows.put("year", &(&1["date"] |> String.split(" ") |> List.last()))
             |> CSV.write(out, header: ["date", "arrivals", "departures", "difference", "year"])

    assert File.read!(out) == Golden.expected("total_arrivals")
  end
end
