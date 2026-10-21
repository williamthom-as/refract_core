defmodule Refract.QueryTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag timeout: 5_000

  alias Refract.Errors.QueryError
  alias Refract.Query
  alias Refract.Query.Result
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

      assert_received {:view, "aws_bill", glob, opts}
      assert glob == Path.join(bills, "*.csv")
      assert Enum.sort(opts) == [format: "csv", types: :text]
      assert_received {:view, "invoice", glob, _opts}
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
      assert_received {:view, "invoice", _glob, opts}
      assert opts[:types] == :infer
    end

    test "format: picks the folders and the glob", %{tmp_dir: dir} do
      sales = folder!(dir, "sales", ["2026.parquet"])
      folder!(dir, "invoice", ["a.csv"])

      assert {:ok, ["sales"]} = Query.views(open!(), dir, format: "parquet")
      assert_received {:view, "sales", glob, opts}
      assert glob == Path.join(sales, "*.parquet")
      assert opts[:format] == "parquet"
    end

    test "a format that is not a plain file extension raises", %{tmp_dir: dir} do
      for format <- [:csv, ".csv", "CSV", ""] do
        assert_raise ArgumentError, ~r/format/, fn ->
          Query.views(open!(), dir, format: format)
        end
      end
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
      assert_received {:view, "bills", ^glob, opts}
      assert Enum.sort(opts) == [format: "csv", types: :text]
    end

    test "format: goes to the engine" do
      assert :ok = Query.view(open!(), "sales", "*.parquet", format: "parquet")
      assert_received {:view, "sales", "*.parquet", opts}
      assert opts[:format] == "parquet"
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

    test "native cells load as their text" do
      row = %{
        "decimal" => Decimal.new("1.23456789012E+11"),
        "integer" => 7,
        "day" => ~D[2026-10-21],
        "at" => ~N[2026-10-21 09:30:00],
        "time" => ~T[09:30:00],
        "flag" => true,
        "blank" => nil
      }

      columns = ["decimal", "integer", "day", "at", "time", "flag", "blank"]

      assert :ok = Query.table(open!(), "names", [row], columns: columns)

      assert_received {:table, "names", ^columns,
                       [
                         [
                           "123456789012",
                           "7",
                           "2026-10-21",
                           "2026-10-21T09:30:00",
                           "09:30:00",
                           "true",
                           nil
                         ]
                       ]}
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

  describe "run/3" do
    test "rows are maps of column to value, columns in select order" do
      query = open!(results: %{"SELECT b, a" => {["b", "a"], [[1, 2], [3, 4]]}})

      assert {:ok, result} = Query.run(query, "SELECT b, a")
      assert is_struct(result, Result)
      assert result.columns == ["b", "a"]
      assert Enum.to_list(result.rows) == [%{"b" => 1, "a" => 2}, %{"b" => 3, "a" => 4}]
    end

    test "rows are read lazily" do
      rows = Stream.concat([[1]], Stream.map([:boom], fn _ -> raise "read too far" end))
      query = open!(results: %{"SELECT a" => {["a"], rows}})

      assert {:ok, result} = Query.run(query, "SELECT a")
      assert Enum.take(result.rows, 1) == [%{"a" => 1}]
    end

    test "params go to the engine" do
      query = open!(results: %{"SELECT a WHERE a = $1" => {["a"], []}})

      assert {:ok, _result} = Query.run(query, "SELECT a WHERE a = $1", ["123"])
      assert_received {:run, "SELECT a WHERE a = $1", ["123"]}
    end

    test "duplicate column names are an error" do
      query = open!(results: %{"SELECT a.id, b.id" => {["id", "id"], [[1, 2]]}})

      assert {:error, {:duplicate_columns, ["id"]}} = Query.run(query, "SELECT a.id, b.id")
    end

    test "an engine error is returned" do
      assert {:error, {:query_error, _message}} = Query.run(open!(), "SELEC 1")
    end

    test "sql must be a string and params a list" do
      assert_raise ArgumentError, ~r/sql/, fn -> Query.run(open!(), :select) end
      assert_raise ArgumentError, ~r/params/, fn -> Query.run(open!(), "SELECT 1", "123") end
    end

    test "result rows write as csv in column order" do
      query = open!(results: %{"SELECT b, a" => {["b", "a"], [["1", "2"]]}})

      {:ok, result} = Query.run(query, "SELECT b, a")
      csv = result.rows |> Refract.CSV.encode(header: result.columns) |> Enum.join()

      assert csv == "b,a\n1,2\n"
    end
  end

  describe "run!/3" do
    test "returns the result" do
      query = open!(results: %{"SELECT a" => {["a"], [[1]]}})

      result = Query.run!(query, "SELECT a")

      assert is_struct(result, Result)
      assert result.columns == ["a"]
    end

    test "raises naming the reason" do
      assert_raise ArgumentError, ~r/query_error/, fn -> Query.run!(open!(), "SELEC 1") end
    end
  end

  describe "close/1" do
    test "gives :ok and later calls are an error" do
      query = open!()

      assert :ok = Query.close(query)
      assert {:error, :closed} = Query.view(query, "bills", "*.csv")
      assert {:error, :closed} = Query.run(query, "SELECT a")
    end

    test "reading rows after close raises a query error" do
      query = open!(results: %{"SELECT a" => {["a"], [[1]]}})

      {:ok, result} = Query.run(query, "SELECT a")
      :ok = Query.close(query)

      assert_raise QueryError, fn -> Enum.to_list(result.rows) end
    end
  end
end
