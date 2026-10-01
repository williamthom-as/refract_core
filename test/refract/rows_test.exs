defmodule Refract.RowsTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  alias Refract.Rows

  @rows [
    %{"id" => "1", "name" => "alice", "note" => ""},
    %{"id" => "2", "name" => "bob", "note" => nil}
  ]

  describe "update/4" do
    test "applies the function to one column" do
      assert @rows |> Rows.update("name", &String.upcase/1) |> Enum.to_list() == [
               %{"id" => "1", "name" => "ALICE", "note" => ""},
               %{"id" => "2", "name" => "BOB", "note" => nil}
             ]
    end

    test "applies the function to each of several columns" do
      rows = [%{"a" => "x", "b" => "y", "c" => "z"}]

      assert rows |> Rows.update(["a", "c"], &String.upcase/1) |> Enum.to_list() == [
               %{"a" => "X", "b" => "y", "c" => "Z"}
             ]
    end

    test "leaves other columns untouched" do
      [row | _] = @rows |> Rows.update("name", fn _ -> "x" end) |> Enum.to_list()

      assert Map.delete(row, "name") == %{"id" => "1", "note" => ""}
    end

    test "unknown column raises, so a typo can never silently skip a transform" do
      assert_raise KeyError, fn ->
        @rows |> Rows.update("nmae", &String.upcase/1) |> Enum.to_list()
      end
    end

    test "skip_blank: true leaves nil and empty string cells alone" do
      rows = @rows |> Rows.update("note", fn _ -> "filled" end, skip_blank: true)

      assert Enum.map(rows, & &1["note"]) == ["", nil]
    end

    test "without skip_blank the function sees blank cells too" do
      rows = @rows |> Rows.update("note", fn _ -> "filled" end)

      assert Enum.map(rows, & &1["note"]) == ["filled", "filled"]
    end

    test "is lazy" do
      test_pid = self()

      rows =
        Rows.update(@rows, "name", fn v ->
          send(test_pid, {:called, v})
          v
        end)

      refute_received {:called, _}
      assert [_] = Enum.take(rows, 1)
      assert_received {:called, "alice"}
      refute_received {:called, "bob"}
    end
  end

  describe "take/2" do
    test "keeps only the listed columns" do
      assert @rows |> Rows.take(["id", "name"]) |> Enum.to_list() == [
               %{"id" => "1", "name" => "alice"},
               %{"id" => "2", "name" => "bob"}
             ]
    end

    test "unknown column raises, same as update" do
      assert_raise KeyError, fn ->
        @rows |> Rows.take(["id", "nmae"]) |> Enum.to_list()
      end
    end

    test "kept long fields no longer hold their whole line" do
      line = String.duplicate("x", 1_000)
      note = binary_part(line, 0, 200)

      assert :binary.referenced_byte_size(note) == 1_000

      [row] = [%{"note" => note, "rest" => line}] |> Rows.take(["note"]) |> Enum.to_list()

      assert row["note"] == note
      assert :binary.referenced_byte_size(row["note"]) == 200
    end

    test "cells that are not strings pass through" do
      rows = [%{"n" => 7, "d" => ~D[2010-01-01], "x" => nil}]

      assert rows |> Rows.take(["n", "d", "x"]) |> Enum.to_list() == rows
    end

    test "is lazy" do
      rows = Stream.map(@rows, fn _ -> raise "read too early" end)

      # building the stream must not read the source (the source raises if read)
      _stream = Rows.take(rows, ["id"])
    end
  end

  describe "put/3" do
    test "adds a column computed from the whole row" do
      rows = [%{"a" => 2, "b" => 3}]

      assert rows |> Rows.put("sum", &(&1["a"] + &1["b"])) |> Enum.to_list() == [
               %{"a" => 2, "b" => 3, "sum" => 5}
             ]
    end

    test "overwrites a column that already exists" do
      assert @rows |> Rows.put("name", &(&1["id"] <> &1["name"])) |> Enum.map(& &1["name"]) ==
               ["1alice", "2bob"]
    end

    test "is lazy" do
      rows = Stream.map(@rows, fn _ -> raise "read too early" end)

      _stream = Rows.put(rows, "x", fn _ -> 1 end)
    end
  end

  describe "copy/3" do
    test "copies a value into a new column" do
      assert @rows |> Rows.copy("name", "display") |> Enum.map(&{&1["name"], &1["display"]}) ==
               [{"alice", "alice"}, {"bob", "bob"}]
    end

    test "overwrites the target, same as put" do
      assert @rows |> Rows.copy("id", "name") |> Enum.map(& &1["name"]) == ["1", "2"]
    end

    test "unknown source column raises" do
      assert_raise KeyError, fn ->
        @rows |> Rows.copy("nmae", "display") |> Enum.to_list()
      end
    end

    test "is lazy" do
      rows = Stream.map(@rows, fn _ -> raise "read too early" end)

      _stream = Rows.copy(rows, "id", "x")
    end
  end

  describe "rename/2" do
    test "renames the mapped columns and keeps the rest" do
      assert @rows |> Rows.rename(%{"id" => "key", "note" => "memo"}) |> Enum.to_list() == [
               %{"key" => "1", "name" => "alice", "memo" => ""},
               %{"key" => "2", "name" => "bob", "memo" => nil}
             ]
    end

    test "swaps two columns" do
      rows = [%{"a" => 1, "b" => 2}]

      assert rows |> Rows.rename(%{"a" => "b", "b" => "a"}) |> Enum.to_list() == [
               %{"a" => 2, "b" => 1}
             ]
    end

    test "unknown column raises" do
      assert_raise KeyError, fn ->
        @rows |> Rows.rename(%{"nmae" => "full_name"}) |> Enum.to_list()
      end
    end

    test "is lazy" do
      rows = Stream.map(@rows, fn _ -> raise "read too early" end)

      _stream = Rows.rename(rows, %{"id" => "key"})
    end
  end

  describe "drop/2" do
    test "removes the listed columns" do
      assert @rows |> Rows.drop(["note", "id"]) |> Enum.to_list() == [
               %{"name" => "alice"},
               %{"name" => "bob"}
             ]
    end

    test "unknown column raises" do
      assert_raise KeyError, fn ->
        @rows |> Rows.drop(["nmae"]) |> Enum.to_list()
      end
    end

    test "is lazy" do
      rows = Stream.map(@rows, fn _ -> raise "read too early" end)

      _stream = Rows.drop(rows, ["id"])
    end
  end

  describe "select/2" do
    test "keeps the mapped columns under their new names" do
      assert @rows |> Rows.select(%{"id" => "key", "name" => "name"}) |> Enum.to_list() == [
               %{"key" => "1", "name" => "alice"},
               %{"key" => "2", "name" => "bob"}
             ]
    end

    test "unknown column raises" do
      assert_raise KeyError, fn ->
        @rows |> Rows.select(%{"nmae" => "name"}) |> Enum.to_list()
      end
    end

    test "kept long fields no longer hold their whole line" do
      line = String.duplicate("x", 1_000)
      note = binary_part(line, 0, 200)

      [row] =
        [%{"note" => note, "rest" => line}] |> Rows.select(%{"note" => "memo"}) |> Enum.to_list()

      assert :binary.referenced_byte_size(row["memo"]) == 200
    end

    test "is lazy" do
      rows = Stream.map(@rows, fn _ -> raise "read too early" end)

      _stream = Rows.select(rows, %{"id" => "key"})
    end
  end

  describe "blank?/1" do
    test "true when every cell is nil, empty or whitespace" do
      assert Rows.blank?(%{"a" => nil, "b" => "", "c" => "  "})
    end

    test "false when any cell has a value" do
      refute Rows.blank?(%{"a" => nil, "b" => "x"})
    end

    test "values that are not strings count as values" do
      refute Rows.blank?(%{"a" => 0})
      refute Rows.blank?(%{"a" => ~D[2010-01-01]})
    end
  end

  describe "from/2" do
    @marked [
      %{"id" => "junk"},
      %{"id" => "START"},
      %{"id" => "1"},
      %{"id" => "START"},
      %{"id" => "2"}
    ]

    test "drops rows before the first match and keeps the match" do
      assert @marked |> Rows.from(&(&1["id"] == "START")) |> Enum.map(& &1["id"]) ==
               ["START", "1", "START", "2"]
    end

    test "nil from the function is not a match" do
      rows = [%{"flag" => nil}, %{"flag" => "x"}]

      assert rows |> Rows.from(& &1["flag"]) |> Enum.to_list() == [%{"flag" => "x"}]
    end

    test "no match gives no rows" do
      assert @marked |> Rows.from(&(&1["id"] == "nope")) |> Enum.to_list() == []
    end

    test "is lazy" do
      rows = Stream.map(@rows, fn _ -> raise "read too early" end)

      _stream = Rows.from(rows, fn _ -> true end)
    end
  end

  describe "until/2" do
    @footed [
      %{"id" => "1"},
      %{"id" => "2"},
      %{"id" => "END"},
      %{"id" => "3"}
    ]

    test "keeps rows before the first match and drops the match" do
      assert @footed |> Rows.until(&(&1["id"] == "END")) |> Enum.map(& &1["id"]) == ["1", "2"]
    end

    test "nil from the function is not a match" do
      rows = [%{"flag" => nil}, %{"flag" => "x"}]

      assert rows |> Rows.until(& &1["flag"]) |> Enum.to_list() == [%{"flag" => nil}]
    end

    test "no match keeps every row" do
      assert @footed |> Rows.until(&(&1["id"] == "nope")) |> Enum.to_list() == @footed
    end

    test "stops reading the source at the match" do
      rows =
        Stream.concat(
          [%{"id" => "1"}, %{"id" => "END"}],
          Stream.map([%{}], fn _ -> raise "read past the match" end)
        )

      assert rows |> Rows.until(&(&1["id"] == "END")) |> Enum.to_list() == [%{"id" => "1"}]
    end

    test "is lazy" do
      rows = Stream.map(@rows, fn _ -> raise "read too early" end)

      _stream = Rows.until(rows, fn _ -> true end)
    end
  end
end
