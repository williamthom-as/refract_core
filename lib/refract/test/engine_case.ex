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
