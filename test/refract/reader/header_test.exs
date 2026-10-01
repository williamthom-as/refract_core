defmodule Refract.Reader.HeaderTest do
  use ExUnit.Case, async: true

  alias Refract.Reader.Header

  describe "normalise/2" do
    test "clean header passes through unchanged" do
      assert Header.normalise(["id", "name", "age"], []) == ["id", "name", "age"]
    end

    test "trims surrounding whitespace" do
      assert Header.normalise(["  Name  ", " Price"], []) == ["Name", "Price"]
    end

    test "strips wrapping quotes" do
      assert Header.normalise(["\"Qty\"", "\"Arrivals (M)\""], []) == ["Qty", "Arrivals (M)"]
    end

    test "trims then strips quotes, in either order of padding" do
      assert Header.normalise(["  \"Qty\"  "], []) == ["Qty"]
    end

    test "leaves inner quotes alone" do
      assert Header.normalise(["the \"best\" col"], []) == ["the \"best\" col"]
    end

    test "blank or whitespace-only header becomes col_<index>, zero based" do
      assert Header.normalise(["id", " ", "name", ""], []) == ["id", "col_1", "name", "col_3"]
    end

    test "nil header cell becomes col_<index>" do
      assert Header.normalise(["id", nil], []) == ["id", "col_1"]
    end

    test "non-string header cell becomes a string" do
      assert Header.normalise(["year", 2024], []) == ["year", "2024"]
    end

    test "duplicates get a numeric suffix, first one keeps the name" do
      assert Header.normalise(["name", "name", "name"], []) == ["name", "name_2", "name_3"]
    end

    test "duplicate check is case sensitive" do
      assert Header.normalise(["id", "name", "name", "Name"], []) == [
               "id",
               "name",
               "name_2",
               "Name"
             ]
    end

    test "duplicates are detected after trimming" do
      assert Header.normalise(["name", " name "], []) == ["name", "name_2"]
    end

    test "output names are always unique" do
      headers = [
        ["name", "name", "name_2"],
        ["name_2", "name", "name"],
        ["col_1", "", "col_1"],
        ["a", "a", "a_2", "a", "a_3"]
      ]

      for header <- headers do
        names = Header.normalise(header, [])

        assert names == Enum.uniq(names),
               "duplicate output names for #{inspect(header)}: #{inspect(names)}"
      end
    end

    test "real headers keep their exact name, generated suffixes skip them" do
      assert Header.normalise(["name", "name", "name_2"], []) == ["name", "name_3", "name_2"]
    end

    test "a real header named like a blank placeholder keeps its name" do
      assert Header.normalise(["col_1", ""], []) == ["col_1", "col_1_2"]
    end

    test "blank and whitespace headers become col_N by position" do
      assert Header.normalise(["identifier", "name", " ", ""], []) ==
               ["identifier", "name", "col_2", "col_3"]
    end
  end

  describe "to_row/2" do
    test "zips a header with a raw row into a map" do
      assert Header.to_row(["id", "name"], ["1", "alice"]) == %{"id" => "1", "name" => "alice"}
    end

    test "keeps cell values untouched, including whitespace" do
      assert Header.to_row(["id", "note"], ["1", " "]) == %{"id" => "1", "note" => " "}
    end
  end

  describe "Reader.stream/3 uses the header" do
    defmodule StubReader do
      use Refract.Reader

      @impl Refract.Reader
      def open({:stream, rows}, _opts), do: {:ok, rows}
    end

    test "header row is normalised before building maps" do
      raw = [["  id ", "", "\"Qty\""], ["1", "x", "3"]]

      assert {:ok, rows} = StubReader.stream({:stream, raw})
      assert Enum.to_list(rows) == [%{"id" => "1", "col_1" => "x", "Qty" => "3"}]
    end
  end
end
