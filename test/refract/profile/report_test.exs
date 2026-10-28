defmodule Refract.Profile.ReportTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag timeout: 10_000

  alias Refract.CSV
  alias Refract.Profile
  alias Refract.Shape
  alias Refract.Table

  @columns %{"account" => ["account"], "cost_centre" => ["cost centre"]}

  defp ledger do
    Shape.new(
      name: "ledger",
      spec: Table.spec(header: [columns: @columns, required: Map.keys(@columns)])
    )
  end

  defp source(cost_centres) do
    rows = Enum.map(cost_centres, &"A-1,#{&1}\n")
    {:string, Enum.join(["Account,Cost Centre\n" | rows])}
  end

  defp rows(cost_centres) do
    {:ok, result} = CSV.profile(source(cost_centres), ledger())
    Profile.rows(result)
  end

  defp variants(rows), do: Enum.map(rows, & &1["variant"])

  test "one row per variant of a single file" do
    assert rows(["Cost Center 1", "costcenter1", "Cost Center 1"]) == [
             %{
               "shape" => "ledger",
               "version" => 1,
               "column" => "cost_centre",
               "most_common" => "Cost Center 1",
               "via" => :normalised,
               "variant" => "Cost Center 1",
               "count" => 2,
               "file" => nil,
               "lines" => "2, 4"
             },
             %{
               "shape" => "ledger",
               "version" => 1,
               "column" => "cost_centre",
               "most_common" => "Cost Center 1",
               "via" => :normalised,
               "variant" => "costcenter1",
               "count" => 1,
               "file" => nil,
               "lines" => "3"
             }
           ]
  end

  test "a folder gives one row per variant per file, files in path order", %{tmp_dir: dir} do
    jan = Path.join(dir, "1_jan.csv")
    feb = Path.join(dir, "2_feb.csv")
    File.write!(jan, "Account,Cost Centre\nA-1,north\nA-2,North\n")
    File.write!(feb, "Account,Cost Centre\nA-1,north\nA-2,north\n")

    {:ok, folders} = Profile.folder(dir, [ledger()])

    assert folders
           |> Profile.rows()
           |> Enum.map(&{&1["variant"], &1["count"], &1["file"], &1["lines"]}) ==
             [
               {"north", 3, jan, "2"},
               {"north", 3, feb, "2, 3"},
               {"North", 1, jan, "3"}
             ]
  end

  test "results by shape name and version, columns by name", %{tmp_dir: dir} do
    columns = Map.put(@columns, "branch", ["branch"])

    v2 =
      Shape.new(
        name: "ledger",
        version: 2,
        spec: Table.spec(header: [columns: columns, required: Map.keys(columns)])
      )

    File.write!(
      Path.join(dir, "1_new.csv"),
      "Account,Cost Centre,Branch\nA-1,north,Sydney\nA-1,North,SYDNEY\n"
    )

    File.write!(Path.join(dir, "2_old.csv"), "Account,Cost Centre\nA-1,south\nA-1,South\n")

    {:ok, folders} = Profile.folder(dir, [ledger(), v2])

    assert folders |> Profile.rows() |> Enum.map(&{&1["version"], &1["column"], &1["variant"]}) ==
             [
               {1, "cost_centre", "south"},
               {1, "cost_centre", "South"},
               {2, "branch", "Sydney"},
               {2, "branch", "SYDNEY"},
               {2, "cost_centre", "north"},
               {2, "cost_centre", "North"}
             ]
  end

  test "a value with invisible differences is shown quoted, hidden characters escaped" do
    assert variants(rows(["north", " north", "north\u00A0", "NORTH"])) ==
             ["north", ~s(" north"), ~S("north\u00A0"), "NORTH"]
  end

  test "most common is quoted the same way" do
    assert [%{"most_common" => ~s(" north")} | _] = rows([" north", " north", "north"])
  end

  test "non text cells are written as text" do
    {:ok, result} =
      Profile.lines([["Account", "Cost Centre"], ["A-1", 12], ["A-2", "12"]], ledger())

    assert result |> Profile.rows() |> variants() == ["12", "12"]
  end

  test "columns without clusters and capped columns add no rows" do
    assert rows(["a", "b", "c"]) == []

    {:ok, result} = CSV.profile(source(["north", "North", "x"]), ledger(), max_distinct: 2)
    assert Profile.rows(result) == []
  end

  test "the header names every key and writes through the csv writer" do
    rows = rows(["north", "North"])

    assert Enum.all?(rows, &(Map.keys(&1) |> Enum.sort() == Enum.sort(Profile.header())))

    assert rows |> CSV.encode(header: Profile.header()) |> Enum.join() ==
             """
             shape,version,column,most_common,via,variant,count,file,lines
             ledger,1,cost_centre,north,normalised,north,1,,2
             ledger,1,cost_centre,north,normalised,North,1,,3
             """
  end
end
