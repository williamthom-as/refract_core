defmodule Refract.Test.EngineCase do
  @moduledoc """
  check/verify a custom query engine will work with Refract.

      use Refract.Test.EngineCase, engine: MyEngine
  """

  defmacro __using__(opts) do
    engine = Keyword.fetch!(opts, :engine)

    quote do
      use ExUnit.Case, async: true

      @moduletag :tmp_dir
      @moduletag timeout: 10_000

      @engine unquote(engine)

      defp open!, do: Refract.Query.open!(engine: @engine)

      defp rows!(query, sql) do
        {:ok, result} = Refract.Query.run(query, sql)

        Enum.to_list(result.rows)
      end

      defp csv!(dir, name, content) do
        path = Path.join(dir, name)
        File.write!(path, content)

        path
      end

      describe "engine conformance" do
        test "opens a session through Refract.Query" do
          assert {:ok, %Refract.Query{engine: @engine}} = Refract.Query.open(engine: @engine)
        end

        test "each open is its own session" do
          assert {:ok, first} = Refract.Query.open(engine: @engine)
          assert {:ok, second} = Refract.Query.open(engine: @engine)

          refute first.state == second.state
        end

        test "a view and a table load", %{tmp_dir: dir} do
          csv!(dir, "rows.csv", "id,name\n1,alice\n")

          assert {:ok, query} = Refract.Query.open(engine: @engine)
          assert :ok = Refract.Query.view(query, "rows", Path.join(dir, "*.csv"))
          assert :ok = Refract.Query.table(query, "names", [%{"id" => "1"}], columns: ["id"])
        end

        test "an unsupported format is an error", %{tmp_dir: dir} do
          assert {:ok, query} = Refract.Query.open(engine: @engine)

          assert {:error, {:unsupported_format, "nope"}} =
                   Refract.Query.view(query, "rows", Path.join(dir, "*.nope"), format: "nope")
        end

        test "a view reads back its rows as text, columns in select order", %{tmp_dir: dir} do
          csv!(dir, "people.csv", "id,name\n2,bob\n1,alice\n")
          query = open!()

          :ok = Refract.Query.view(query, "people", Path.join(dir, "people.csv"))

          assert {:ok, result} =
                   Refract.Query.run(query, "SELECT name, id FROM people ORDER BY id")

          assert result.columns == ["name", "id"]

          assert Enum.to_list(result.rows) == [
                   %{"name" => "alice", "id" => "1"},
                   %{"name" => "bob", "id" => "2"}
                 ]
        end

        test "rows can be read more than once", %{tmp_dir: dir} do
          csv!(dir, "people.csv", "id,name\n1,alice\n2,bob\n")
          query = open!()

          :ok = Refract.Query.view(query, "people", Path.join(dir, "people.csv"))
          {:ok, result} = Refract.Query.run(query, "SELECT id FROM people ORDER BY id")

          assert Enum.take(result.rows, 1) == [%{"id" => "1"}]
          assert Enum.to_list(result.rows) == [%{"id" => "1"}, %{"id" => "2"}]
        end

        test "files in one view join by name, missing cells nil", %{tmp_dir: dir} do
          csv!(dir, "a.csv", "sku,total\n1,3\n")
          csv!(dir, "b.csv", "sku,kg\n2,4\n")
          query = open!()

          :ok = Refract.Query.view(query, "invoice", Path.join(dir, "*.csv"))

          assert rows!(query, "SELECT sku, total, kg FROM invoice ORDER BY sku") == [
                   %{"sku" => "1", "total" => "3", "kg" => nil},
                   %{"sku" => "2", "total" => nil, "kg" => "4"}
                 ]
        end

        test "leading zeros stay text", %{tmp_dir: dir} do
          csv!(dir, "accounts.csv", "id\n007\n")
          query = open!()

          :ok = Refract.Query.view(query, "accounts", Path.join(dir, "accounts.csv"))

          assert rows!(query, "SELECT id FROM accounts") == [%{"id" => "007"}]
        end

        test "a table reads back its rows" do
          query = open!()

          :ok =
            Refract.Query.table(query, "names", [%{"id" => "007", "name" => nil}],
              columns: ["id", "name"]
            )

          assert rows!(query, "SELECT id, name FROM names") == [%{"id" => "007", "name" => nil}]
        end

        test "params bind", %{tmp_dir: dir} do
          csv!(dir, "people.csv", "id,name\n1,alice\n2,bob\n")
          query = open!()

          :ok = Refract.Query.view(query, "people", Path.join(dir, "people.csv"))

          assert {:ok, result} =
                   Refract.Query.run(query, "SELECT name FROM people WHERE id = $1", ["2"])

          assert Enum.to_list(result.rows) == [%{"name" => "bob"}]
        end

        test "duplicate column names are an error" do
          query = open!()

          :ok = Refract.Query.table(query, "names", [%{"id" => "1"}], columns: ["id"])

          assert {:error, {:duplicate_columns, ["id"]}} =
                   Refract.Query.run(query, "SELECT a.id, b.id FROM names a, names b")
        end

        test "a sql error is a query error" do
          assert {:error, {:query_error, _message}} = Refract.Query.run(open!(), "SELEC 1")
        end

        test "run after close is an error, reading rows after close raises" do
          query = open!()

          :ok = Refract.Query.table(query, "names", [%{"id" => "1"}], columns: ["id"])
          {:ok, result} = Refract.Query.run(query, "SELECT id FROM names")
          :ok = Refract.Query.close(query)

          assert {:error, :closed} = Refract.Query.run(query, "SELECT id FROM names")
          assert_raise Refract.Errors.QueryError, fn -> Enum.to_list(result.rows) end
        end

        test "close gives :ok" do
          assert {:ok, query} = Refract.Query.open(engine: @engine)
          assert :ok = Refract.Query.close(query)
        end

        test "a view or a table after close is an error", %{tmp_dir: dir} do
          csv!(dir, "rows.csv", "id,name\n1,alice\n")

          assert {:ok, query} = Refract.Query.open(engine: @engine)
          assert :ok = Refract.Query.close(query)

          assert {:error, :closed} = Refract.Query.view(query, "rows", Path.join(dir, "*.csv"))

          assert {:error, :closed} =
                   Refract.Query.table(query, "names", [%{"id" => "1"}], columns: ["id"])
        end
      end
    end
  end
end
