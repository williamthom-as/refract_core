defmodule Refract.QueryTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag timeout: 5_000

  alias Refract.Query
  alias Refract.Table
  alias Refract.TestEngines

  defp open!(opts \\ []), do: Query.open!([engine: TestEngines.Stub] ++ opts)

  defp folder!(dir, name, files) do
    path = Path.join(dir, name)
    File.mkdir_p!(path)

    for file <- files, do: File.write!(Path.join(path, file), "id\n1\n")

    path
  end

  describe "open/1" do
    test "opens through the engine given" do
      assert {:ok, %Query{engine: TestEngines.Stub, state: %{opts: []}}} =
               Query.open(engine: TestEngines.Stub)
    end

    test "engine is required" do
      assert_raise KeyError, ~r/engine/, fn -> Query.open() end
    end

    test "an engine without open/1 raises" do
      assert_raise ArgumentError, ~r/engine/, fn -> Query.open(engine: String) end
    end

    test "an engine error is returned" do
      assert {:error, :refused} = Query.open(engine: TestEngines.Refusing)
    end

    test "other options go to the engine" do
      assert {:ok, %Query{state: %{opts: [path: "q.duckdb"]}}} =
               Query.open(engine: TestEngines.Stub, path: "q.duckdb")
    end
  end

  describe "open!/1" do
    test "returns the session" do
      assert %Query{engine: TestEngines.Stub} = open!()
    end

    test "raises naming the reason" do
      assert_raise ArgumentError, ~r/refused/, fn -> Query.open!(engine: TestEngines.Refusing) end
    end
  end

  describe "views/3" do
    test "a view per subfolder holding csv files, names sorted", %{tmp_dir: dir} do
      bills = folder!(dir, "aws_bill", ["2026_09.csv", "2026_10.csv"])
      invoices = folder!(dir, "invoice", ["acme.csv"])

      assert {:ok, ["aws_bill", "invoice"]} = Query.views(open!(), dir)

      assert_received {:view, "aws_bill", glob, [types: :text]}
      assert glob == Path.join(bills, "*.csv")
      assert_received {:view, "invoice", glob, [types: :text]}
      assert glob == Path.join(invoices, "*.csv")
    end

    test "folders starting with an underscore are skipped", %{tmp_dir: dir} do
      folder!(dir, "_unknown", ["a.csv"])
      folder!(dir, "invoice", ["a.csv"])

      assert {:ok, ["invoice"]} = Query.views(open!(), dir)
    end

    test "folders without csv files are skipped", %{tmp_dir: dir} do
      folder!(dir, "empty", [])
      folder!(dir, "notes", ["readme.txt"])
      folder!(dir, "invoice", ["a.csv"])

      assert {:ok, ["invoice"]} = Query.views(open!(), dir)
    end

    test "files beside the folders are ignored", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "loose.csv"), "id\n1\n")
      folder!(dir, "invoice", ["a.csv"])

      assert {:ok, ["invoice"]} = Query.views(open!(), dir)
    end

    test "a folder name that is not a plain identifier raises naming it", %{tmp_dir: dir} do
      folder!(dir, "AWS Bill", ["a.csv"])

      assert_raise ArgumentError, ~r/AWS Bill/, fn -> Query.views(open!(), dir) end
    end

    test "types: :infer goes to the engine", %{tmp_dir: dir} do
      folder!(dir, "invoice", ["a.csv"])

      assert {:ok, ["invoice"]} = Query.views(open!(), dir, types: :infer)
      assert_received {:view, "invoice", _glob, [types: :infer]}
    end

    test "unknown types raise", %{tmp_dir: dir} do
      assert_raise ArgumentError, ~r/types/, fn -> Query.views(open!(), dir, types: :guess) end
    end

    test "a missing dir is an error", %{tmp_dir: dir} do
      assert {:error, :enoent} = Query.views(open!(), Path.join(dir, "missing"))
    end

    test "an empty dir gives no views", %{tmp_dir: dir} do
      assert {:ok, []} = Query.views(open!(), dir)
    end
  end

  describe "view/4" do
    test "passes the glob to the engine", %{tmp_dir: dir} do
      glob = Path.join([dir, "aws_bill", "2026-*", "*.csv"])

      assert :ok = Query.view(open!(), "bills", glob)
      assert_received {:view, "bills", ^glob, [types: :text]}
    end

    test "a name that is not a plain identifier raises" do
      assert_raise ArgumentError, ~r/2026 bills/, fn ->
        Query.view(open!(), "2026 bills", "*.csv")
      end
    end
  end

  describe "table/4" do
    test "a located table loads its header and rows in header order" do
      spec = Table.spec(header: [columns: %{"sku" => ["sku"], "item" => ["item"]}])

      {:ok, table} = Refract.CSV.locate({:string, "sku,item\n1,apple\n2,pear\n"}, spec)

      assert :ok = Query.table(open!(), "names", table)
      assert_received {:table, "names", ["sku", "item"], [["1", "apple"], ["2", "pear"]]}
    end

    test "rows load in the order of columns:, missing cells nil" do
      rows = [%{"a" => "1", "b" => "2"}, %{"a" => "3"}]

      assert :ok = Query.table(open!(), "names", rows, columns: ["b", "a"])
      assert_received {:table, "names", ["b", "a"], [["2", "1"], [nil, "3"]]}
    end

    test "rows without columns: raise" do
      assert_raise KeyError, ~r/columns/, fn -> Query.table(open!(), "names", [%{"a" => "1"}]) end
    end

    test "a name that is not a plain identifier raises" do
      assert_raise ArgumentError, ~r/Names/, fn ->
        Query.table(open!(), "Names", [%{"a" => "1"}], columns: ["a"])
      end
    end
  end

  describe "close/1" do
    test "gives :ok and later calls are an error" do
      query = open!()

      assert :ok = Query.close(query)
      assert {:error, :closed} = Query.view(query, "bills", "*.csv")
    end
  end
end
