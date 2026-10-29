defmodule Refract.E2E.LongToWideTest do
  use ExUnit.Case, async: true

  @moduletag :e2e
  @moduletag :tmp_dir
  @moduletag timeout: 10_000

  alias Refract.Clean
  alias Refract.CSV
  alias Refract.Golden
  alias Refract.Parse
  alias Refract.Rows

  @input Golden.path("long_to_wide", "input.csv")

  defp reading_types do
    {:ok, rows} = CSV.stream(@input)

    rows
    |> Stream.reject(&Rows.blank?(&1, "Reading Type"))
    |> Rows.distinct("Reading Type")
    |> Stream.map(&Clean.slug(&1["Reading Type"]))
    |> Enum.sort()
  end

  defp readings do
    {:ok, rows} = CSV.stream(@input)

    rows
    |> Stream.reject(&Rows.blank?/1)
    |> Rows.fill_down("Asset Tag")
    |> Rows.update("Taken At", &Parse.datetime!(&1, formats: [:dmy]))
    |> Rows.update("Reading Type", &Clean.slug/1)
    |> Rows.rename(&Clean.slug/1)
  end

  defp widen(lines, types) do
    lines = Enum.sort_by(lines, & &1["taken_at"], NaiveDateTime)
    present = Enum.reject(lines, &Rows.blank?(&1, "reading_value"))

    latest =
      Map.new(types, fn type ->
        line = present |> Enum.filter(&(&1["reading_type"] == type)) |> List.last()

        {type, line && line["reading_value"]}
      end)

    Map.merge(latest, %{
      "readings" => Enum.count(present),
      "latest_at" => List.last(lines)["taken_at"]
    })
  end

  test "reading types come from the data, slugged and sorted" do
    assert reading_types() == ["flow_rate", "pressure_kpa", "temperature"]
  end

  test "the id fills down and the blank line is dropped first" do
    assert readings() |> Enum.map(& &1["asset_tag"]) ==
             ~w(PUMP-01 PUMP-01 PUMP-01 PUMP-02 PUMP-02 PUMP-03 PUMP-03)
  end

  test "one row per asset with the latest of each reading", %{tmp_dir: dir} do
    out = Path.join(dir, "long_to_wide.csv")
    types = reading_types()

    assert :ok =
             readings()
             |> Rows.group(by: "asset_tag", into: &widen(&1, types))
             |> CSV.write(out, header: ["asset_tag", "readings"] ++ types ++ ["latest_at"])

    assert File.read!(out) == Golden.expected("long_to_wide")
  end

  test "the wide rows can be cut back to the readings alone" do
    [first | _] =
      readings()
      |> Rows.group(by: "asset_tag", into: &widen(&1, reading_types()))
      |> Rows.take(&(&1 in reading_types()))
      |> Enum.to_list()

    assert first == %{"flow_rate" => nil, "pressure_kpa" => "425", "temperature" => "61"}
  end
end
