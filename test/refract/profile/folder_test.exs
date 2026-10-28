defmodule Refract.Profile.FolderTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag timeout: 10_000

  alias Refract.Profile
  alias Refract.Profile.Cluster
  alias Refract.Profile.Column
  alias Refract.Profile.Folders
  alias Refract.Profile.Result
  alias Refract.Profile.Variant
  alias Refract.Shape
  alias Refract.Table

  @ledger_columns %{
    "account" => ["account"],
    "cost_centre" => ["cost centre"],
    "amount" => ["amount"]
  }

  defp ledger(name \\ "ledger", version \\ 1, columns \\ @ledger_columns) do
    Shape.new(
      name: name,
      version: version,
      spec:
        Table.spec(
          header: [columns: columns, required: Map.keys(columns)],
          row: [match: %{"amount" => :number}]
        )
    )
  end

  defp statement do
    Shape.new(
      name: "statement",
      spec:
        Table.spec(
          header: [columns: %{"date" => ["date"], "payee" => ["payee"]}],
          row: [match: %{"date" => :date}]
        )
    )
  end

  defp write(dir, name, content) do
    path = Path.join(dir, name)
    File.write!(path, content)
    path
  end

  defp ledger_file(dir, name, cost_centres) do
    rows = Enum.map(cost_centres, &"A-1,#{&1},1.00\n")
    write(dir, name, Enum.join(["Account,Cost Centre,Amount\n" | rows]))
  end

  defp profile(dir, shapes, opts \\ []) do
    assert {:ok, %Folders{} = folder} = Profile.folder(dir, shapes, opts)
    folder
  end

  defp cost_centre(%Folders{results: results}, key \\ {"ledger", 1}),
    do: results[key].columns["cost_centre"]

  describe "across files" do
    test "spellings in different files form one cluster, with lines by file", %{tmp_dir: dir} do
      jan = ledger_file(dir, "1_jan.csv", ["Cost Center 1", "Cost Center 1"])
      feb = ledger_file(dir, "2_feb.csv", ["north", "costcenter1"])

      assert %Column{
               clusters: [
                 %Cluster{
                   most_common: "Cost Center 1",
                   variants: [
                     %Variant{value: "Cost Center 1", count: 2, files: %{^jan => [2, 3]}},
                     %Variant{value: "costcenter1", count: 1, files: %{^feb => [3]}}
                   ]
                 }
               ]
             } = dir |> profile([ledger()]) |> cost_centre()
    end

    test "one variant keeps its lines in every file", %{tmp_dir: dir} do
      jan = ledger_file(dir, "1_jan.csv", ["north", "North"])
      feb = ledger_file(dir, "2_feb.csv", ["x", "north"])

      assert %Column{clusters: [%Cluster{variants: [north, _north]}]} =
               dir |> profile([ledger()]) |> cost_centre()

      assert %Variant{value: "north", count: 2, files: %{^jan => [2], ^feb => [3]}} = north
    end

    test "rows and files add up", %{tmp_dir: dir} do
      jan = ledger_file(dir, "1_jan.csv", ["a", "b"])
      feb = ledger_file(dir, "2_feb.csv", ["c"])

      assert %Result{rows: 3, files: [^jan, ^feb], shape: %Shape{name: "ledger"}} =
               profile(dir, [ledger()]).results[{"ledger", 1}]
    end

    test "a column a file lacks adds no blanks", %{tmp_dir: dir} do
      columns = Map.put(@ledger_columns, "branch", ["branch"])

      shape =
        Shape.new(
          name: "ledger",
          spec:
            Table.spec(
              header: [columns: columns, required: ["account", "amount"], min_matches: 3]
            )
        )

      write(dir, "1_jan.csv", "Account,Cost Centre,Amount,Branch\nA-1,north,1.00,Sydney\n")
      ledger_file(dir, "2_feb.csv", ["north", "North"])

      assert %Result{rows: 3, columns: %{"branch" => %Column{blanks: 0, distinct: 1}}} =
               profile(dir, [shape]).results[{"ledger", 1}]
    end

    test "first seen follows file order", %{tmp_dir: dir} do
      ledger_file(dir, "1_jan.csv", ["south"])
      ledger_file(dir, "2_feb.csv", ["SOUTH"])

      assert %Column{clusters: [%Cluster{most_common: "south"}]} =
               dir |> profile([ledger()]) |> cost_centre()
    end

    test "a folder variant has files, not lines", %{tmp_dir: dir} do
      ledger_file(dir, "1_jan.csv", ["north", "North"])

      assert %Column{clusters: [%Cluster{variants: [%Variant{lines: []} | _]}]} =
               dir |> profile([ledger()]) |> cost_centre()
    end
  end

  describe "shapes" do
    test "one result per shape, keyed by name and version", %{tmp_dir: dir} do
      jan = ledger_file(dir, "1_jan.csv", ["north"])
      bank = write(dir, "2_bank.csv", "Date,Payee\n2026-10-01,Acme\n2026-10-02,ACME\n")

      folder = profile(dir, [ledger(), statement()])

      assert folder.results |> Map.keys() |> Enum.sort() == [{"ledger", 1}, {"statement", 1}]
      assert %Result{files: [^jan]} = folder.results[{"ledger", 1}]

      assert %Result{files: [^bank], columns: %{"payee" => %Column{clusters: [_cluster]}}} =
               folder.results[{"statement", 1}]
    end

    test "two versions of a shape are two results", %{tmp_dir: dir} do
      v2_columns = Map.put(@ledger_columns, "branch", ["branch"])
      old = ledger_file(dir, "1_old.csv", ["north"])
      new = write(dir, "2_new.csv", "Account,Cost Centre,Amount,Branch\nA-1,North,1.00,Sydney\n")

      folder = profile(dir, [ledger(), ledger("ledger", 2, v2_columns)])

      assert %Result{files: [^old]} = folder.results[{"ledger", 1}]
      assert %Result{files: [^new]} = folder.results[{"ledger", 2}]
    end

    test "a shape no file matched has no result", %{tmp_dir: dir} do
      ledger_file(dir, "1_jan.csv", ["north"])

      assert profile(dir, [ledger(), statement()]).results |> Map.keys() == [{"ledger", 1}]
    end
  end

  describe "skipped" do
    test "a file that fails partway is skipped and adds nothing", %{tmp_dir: dir} do
      rows = Enum.map(1..120, fn _ -> "A-1,north,1.00\n" end)

      bad =
        write(
          dir,
          "1_bad.csv",
          Enum.join(["Account,Cost Centre,Amount\n" | rows]) <> "A-1,\"north,1.00\n"
        )

      assert %Folders{results: results, skipped: [{^bad, {:parse_error, _message}}]} =
               profile(dir, [ledger()])

      assert results == %{}
    end

    test "unknown and unreadable files are skipped with the reason", %{tmp_dir: dir} do
      ledger_file(dir, "1_jan.csv", ["north"])
      notes = write(dir, "2_notes.csv", "Topic,Owner\nbudget,sam\n")
      text = write(dir, "3_readme.txt", "notes\n")

      assert %Folders{skipped: [{^notes, :unknown}, {^text, {:unsupported, "txt"}}]} =
               profile(dir, [ledger()])
    end

    test "an ambiguous file is skipped", %{tmp_dir: dir} do
      jan = ledger_file(dir, "1_jan.csv", ["north"])

      assert %Folders{results: results, skipped: [{^jan, :ambiguous}]} =
               profile(dir, [ledger("ledger"), ledger("ledger_copy")])

      assert results == %{}
    end

    test "an empty folder has no results", %{tmp_dir: dir} do
      assert %Folders{results: results, skipped: []} = profile(dir, [ledger()])
      assert results == %{}
    end

    test "a missing folder is an error", %{tmp_dir: dir} do
      assert {:error, :enoent} = Profile.folder(Path.join(dir, "missing"), [ledger()])
    end
  end

  describe "options" do
    test "max_lines counts across the folder, first files first", %{tmp_dir: dir} do
      jan = ledger_file(dir, "1_jan.csv", ["north", "North"])
      feb = ledger_file(dir, "2_feb.csv", ["North", "North"])

      assert %Column{clusters: [%Cluster{variants: [north, _north]}]} =
               dir |> profile([ledger()], max_lines: 2) |> cost_centre()

      assert %Variant{value: "North", count: 3, files: files} = north
      assert files == %{jan => [3], feb => [2]}
    end

    test "max_distinct counts across the folder", %{tmp_dir: dir} do
      ledger_file(dir, "1_jan.csv", ["a", "b"])
      ledger_file(dir, "2_feb.csv", ["c"])

      assert %Column{capped: false} = dir |> profile([ledger()], max_distinct: 3) |> cost_centre()
      assert %Column{capped: true} = dir |> profile([ledger()], max_distinct: 2) |> cost_centre()
    end

    test "except leaves columns out", %{tmp_dir: dir} do
      ledger_file(dir, "1_jan.csv", ["north"])

      assert %Result{columns: columns} =
               profile(dir, [ledger()], except: ["account", "amount"]).results[{"ledger", 1}]

      assert Map.keys(columns) == ["cost_centre"]
    end

    test "header_row is refused", %{tmp_dir: dir} do
      assert_raise ArgumentError, fn -> Profile.folder(dir, [ledger()], header_row: 1) end
    end
  end
end
