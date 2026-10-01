defmodule Refract.CSV.StreamTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  @csv Path.expand("../../fixtures/csv", __DIR__)

  @golden Path.expand("../../fixtures/golden", __DIR__)

  defp fixture(name), do: Path.join(@csv, name)

  defp rows!(source, opts \\ []) do
    assert {:ok, rows} = Refract.CSV.stream(source, opts)

    Enum.to_list(rows)
  end

  describe "sources" do
    test "path" do
      assert rows!(fixture("comma_in_quoted.csv")) == [
               %{"id" => "1", "address" => "4 Farm Rd, Orange"},
               %{"id" => "2", "address" => "12 Market St, Sydney, NSW"}
             ]
    end

    test "{:string, binary}" do
      assert rows!({:string, "id,name\n1,alice\n2,bob\n"}) == [
               %{"id" => "1", "name" => "alice"},
               %{"id" => "2", "name" => "bob"}
             ]
    end

    test "{:stream, enumerable} of lines" do
      lines = ["id,name\n", "1,alice\n", "2,bob\n"]

      assert rows!({:stream, lines}) == [
               %{"id" => "1", "name" => "alice"},
               %{"id" => "2", "name" => "bob"}
             ]
    end

    test "missing file fails fast, before any stream" do
      assert {:error, :enoent} = Refract.CSV.stream(fixture("does_not_exist.csv"))
    end
  end

  describe "parsing hazards" do
    test "strips a utf8 bom from the first header" do
      assert rows!(fixture("bom.csv")) == [%{"id" => "1", "name" => "alice"}]
    end

    test "newline inside a quoted field" do
      assert rows!(fixture("quoted_newline.csv")) == [
               %{"id" => "1", "note" => "line one\nline two"},
               %{"id" => "2", "note" => "plain"}
             ]
    end

    test "escaped double quotes" do
      assert rows!(fixture("escaped_quotes.csv")) == [
               %{"id" => "1", "quote" => "she said \"hi\""},
               %{"id" => "2", "quote" => "\"wrapped\""}
             ]
    end

    test "crlf line endings" do
      assert rows!(fixture("crlf.csv")) == [
               %{"id" => "1", "name" => "alice"},
               %{"id" => "2", "name" => "bob"}
             ]
    end

    test "last line without a trailing newline" do
      assert rows!(fixture("no_trailing_newline.csv")) == [
               %{"id" => "1", "name" => "alice"},
               %{"id" => "2", "name" => "bob"}
             ]
    end

    test "unicode bytes preserved" do
      rows = rows!(fixture("unicode.csv"))

      assert Enum.map(rows, & &1["name"]) == ["Zoë", "山田", "Émile", "Noe\u0308l"]
    end

    test "header only gives an empty stream" do
      assert rows!(fixture("header_only.csv")) == []
    end

    test "empty file gives an empty stream" do
      assert rows!(fixture("empty.csv")) == []
    end
  end

  describe "header normalisation" do
    test "trailing empty headers become col_<index>" do
      assert rows!(fixture("trailing_empty_columns.csv")) == [
               %{"id" => "1", "name" => "alice", "col_2" => "", "col_3" => ""},
               %{"id" => "2", "name" => "bob", "col_2" => "", "col_3" => ""}
             ]
    end

    test "blank header cells get generated names" do
      rows = rows!(Path.join(@golden, "empty_columns/input.csv"))

      assert rows == [
               %{"identifier" => "1", "name" => "john smith", "col_2" => " ", "col_3" => ""},
               %{"identifier" => "2", "name" => "lean davis", "col_2" => " ", "col_3" => ""}
             ]
    end
  end

  describe "options" do
    test "separator: \";\"" do
      assert rows!(fixture("semicolon.csv"), separator: ";") == [
               %{"id" => "1", "name" => "alice", "amount" => "1,5"},
               %{"id" => "2", "name" => "bob", "amount" => "2;5"}
             ]
    end

    test "separator: \"\\t\"" do
      assert rows!(fixture("tab.tsv"), separator: "\t") == [
               %{"id" => "1", "name" => "alice"},
               %{"id" => "2", "name" => "bob\tjr"}
             ]
    end

    test "unsupported separator is an error, not a crash" do
      assert {:error, {:unsupported_separator, "~"}} =
               Refract.CSV.stream({:string, "a~b\n1~2\n"}, separator: "~")
    end

    test "skip: drops parsed rows above the header" do
      rows = rows!(Path.join(@golden, "bad_data/input.csv"), skip: 3)

      assert hd(rows) == %{
               "identifier" => "1",
               "name" => "john smith",
               "age" => "25",
               "city" => "New York",
               "empty" => ""
             }
    end
  end
end
