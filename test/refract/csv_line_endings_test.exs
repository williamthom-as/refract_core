defmodule Refract.CSVLineEndingsTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag timeout: 10_000

  alias Refract.CSV
  alias Refract.Shape
  alias Refract.Table

  defp rows!(source) do
    {:ok, rows} = CSV.stream(source)

    Enum.to_list(rows)
  end

  defp numbers,
    do: [%{"a" => "1", "b" => "2"}, %{"a" => "3", "b" => "4"}, %{"a" => "5", "b" => "6"}]

  describe "reading" do
    test "\\n and \\r\\n mixed in one file" do
      assert rows!({:string, "a,b\n1,2\r\n3,4\n5,6\r\n"}) == numbers()
    end

    test "a \\r\\n split across stream chunks is one line end, no blank row" do
      source = {:stream, ["a,b\r", "\n1,2\r", "\n3,4\r\n5,6\r", "\n"]}

      assert rows!(source) == numbers()
    end

    test "doubled \\r\\r\\n endings give no blank rows" do
      rows = rows!({:string, "a,b\r\r\n1,2\r\r\n3,4\r\r\n5,6\r\r\n"})

      assert Enum.map(rows, & &1["a"]) == ["1", "3", "5"]
    end

    test "a bare \\r inside a cell stays in the cell" do
      assert rows!({:string, "a,b\nx\ry,2\n"}) == [%{"a" => "x\ry", "b" => "2"}]
    end

    test "\\r and \\r\\n inside quoted cells are kept" do
      assert rows!({:string, "a,b\n\"x\ry\",2\n\"p\r\nq\",4\n"}) == [
               %{"a" => "x\ry", "b" => "2"},
               %{"a" => "p\r\nq", "b" => "4"}
             ]
    end

    test "a lone \\r in an \\n file is not a line end, facts reports the file as mixed" do
      assert {:ok, %{line_endings: :mixed}} = CSV.facts({:string, "a,b\n1,2\r3,4\n5,6\n"})
    end
  end

  describe "\\r only files are an error, not zero rows" do
    defp shape do
      Shape.new(
        name: "numbers",
        spec: Table.spec(header: [columns: %{"a" => ["a"], "b" => ["b"]}])
      )
    end

    test "a string" do
      assert {:error, {:unsupported_line_endings, :cr}} = CSV.stream({:string, "a,b\r1,2\r3,4\r"})
    end

    test "a file on disk", %{tmp_dir: dir} do
      path = Path.join(dir, "old_mac.csv")
      File.write!(path, "a,b\r1,2\r3,4\r5,6")

      assert {:error, {:unsupported_line_endings, :cr}} = CSV.stream(path)
    end

    test "locate and classify return it" do
      source = {:string, "a,b\r1,2\r3,4\r"}

      assert {:error, {:unsupported_line_endings, :cr}} = CSV.locate(source, shape().spec)
      assert {:error, {:unsupported_line_endings, :cr}} = CSV.classify(source, [shape()])
    end

    test "facts still describes it" do
      assert {:ok, %{line_endings: :cr}} = CSV.facts({:string, "a,b\r1,2\r"})
    end
  end

  describe "writing" do
    test "a cell holding a \\r is quoted and reads back the same", %{tmp_dir: dir} do
      path = Path.join(dir, "out.csv")
      rows = [%{"a" => "x\ry", "b" => "2"}]

      :ok = CSV.write(rows, path)

      assert File.read!(path) == "a,b\n\"x\ry\",2\n"
      assert rows!(path) == rows
    end
  end
end
