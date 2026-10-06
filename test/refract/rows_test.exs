defmodule Refract.RowsTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  alias Refract.Rows

  @rows [
    %{"id" => "1", "name" => "alice", "note" => ""},
    %{"id" => "2", "name" => "bob", "note" => nil}
  ]

  defp counting(fun) do
    counter = :counters.new(1, [])

    {fn col ->
       :counters.add(counter, 1, 1)
       fun.(col)
     end, fn -> :counters.get(counter, 1) end}
  end

  @repeated List.duplicate(%{"Id" => "1", "Name" => "alice", "Note" => ""}, 4)

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

    test "a two argument function also gets the row and column" do
      rows =
        Rows.update(@rows, "name", fn value, ctx -> "#{ctx.row["id"]}-#{ctx.column}-#{value}" end)

      assert Enum.map(rows, & &1["name"]) == ["1-name-alice", "2-name-bob"]
    end

    test "ctx is a Rows.Ctx struct" do
      [ctx] =
        [%{"a" => "x"}] |> Rows.update("a", fn _value, ctx -> ctx end) |> Enum.map(& &1["a"])

      assert is_struct(ctx, Rows.Ctx)
      assert ctx.row == %{"a" => "x"}
      assert ctx.column == "a"
    end

    test "ctx row is the row before this update so column order does not matter" do
      rows = [%{"a" => "1", "b" => "2"}]
      swap = fn _value, ctx -> if ctx.column == "a", do: ctx.row["b"], else: ctx.row["a"] end

      assert rows |> Rows.update(["a", "b"], swap) |> Enum.to_list() == [
               %{"a" => "2", "b" => "1"}
             ]

      assert rows |> Rows.update(["b", "a"], swap) |> Enum.to_list() == [
               %{"a" => "2", "b" => "1"}
             ]
    end

    test "skip_blank still skips with a two argument function" do
      rows = Rows.update(@rows, "note", fn _value, _ctx -> "filled" end, skip_blank: true)

      assert Enum.map(rows, & &1["note"]) == ["", nil]
    end

    test "functions of other arities raise" do
      assert_raise ArgumentError, fn -> Rows.update(@rows, "name", fn _a, _b, _c -> "x" end) end
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

    test "a function keeps the columns it is true for" do
      rows = [%{"q1_total" => "10", "q2_total" => "12", "id" => "1"}]

      assert rows |> Rows.take(&String.ends_with?(&1, "_total")) |> Enum.to_list() == [
               %{"q1_total" => "10", "q2_total" => "12"}
             ]
    end

    test "a function runs once per column name, not per row" do
      {fun, calls} = counting(&(&1 == "Id"))

      assert @repeated |> Rows.take(fun) |> Enum.to_list() == List.duplicate(%{"Id" => "1"}, 4)
      assert calls.() == 3
    end

    test "a function matching nothing gives empty rows" do
      assert @rows |> Rows.take(&String.starts_with?(&1, "x")) |> Enum.to_list() == [%{}, %{}]
    end

    test "is lazy" do
      rows = Stream.map(@rows, fn _ -> raise "read too early" end)

      # building the stream must not read the source (the source raises if read)
      _stream = Rows.take(rows, ["id"])
      _stream = Rows.take(rows, &(&1 == "id"))
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

    test "a function renames every column" do
      rows = [%{"Invoice Number" => "1", "Date of Issue" => "2026/10/02"}]

      assert rows |> Rows.rename(&Refract.Clean.slug/1) |> Enum.to_list() == [
               %{"invoice_number" => "1", "date_of_issue" => "2026/10/02"}
             ]
    end

    test "a map renaming onto a column that stays raises" do
      rows = [%{"a" => 1, "b" => 2}]

      assert_raise ArgumentError, ~r/clashes/, fn ->
        rows |> Rows.rename(%{"a" => "b"}) |> Enum.to_list()
      end
    end

    test "a map sending two columns to one name raises" do
      rows = [%{"a" => 1, "b" => 2}]

      assert_raise ArgumentError, ~r/clashes/, fn ->
        rows |> Rows.rename(%{"a" => "c", "b" => "c"}) |> Enum.to_list()
      end
    end

    test "a function runs once per column name, not per row" do
      {fun, calls} = counting(&String.downcase/1)

      assert @repeated |> Rows.rename(fun) |> Enum.to_list() ==
               List.duplicate(%{"id" => "1", "name" => "alice", "note" => ""}, 4)

      assert calls.() == 3
    end

    test "a function that sends two columns to one name raises" do
      rows = [%{"a" => 1, "A" => 2}]

      assert_raise ArgumentError, ~r/clashes/, fn ->
        rows |> Rows.rename(&String.downcase/1) |> Enum.to_list()
      end
    end

    test "is lazy" do
      rows = Stream.map(@rows, fn _ -> raise "read too early" end)

      _stream = Rows.rename(rows, %{"id" => "key"})
      _stream = Rows.rename(rows, &String.upcase/1)
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

    test "a function removes the columns it is true for" do
      rows = [%{"id" => "1", "col_2" => "", "col_3" => ""}]

      assert rows |> Rows.drop(&String.starts_with?(&1, "col_")) |> Enum.to_list() == [
               %{"id" => "1"}
             ]
    end

    test "a function runs once per column name, not per row" do
      {fun, calls} = counting(&(&1 == "Note"))

      assert @repeated |> Rows.drop(fun) |> Enum.to_list() ==
               List.duplicate(%{"Id" => "1", "Name" => "alice"}, 4)

      assert calls.() == 3
    end

    test "a function matching nothing leaves the rows alone" do
      assert @rows |> Rows.drop(&String.starts_with?(&1, "x")) |> Enum.to_list() == @rows
    end

    test "is lazy" do
      rows = Stream.map(@rows, fn _ -> raise "read too early" end)

      _stream = Rows.drop(rows, ["id"])
      _stream = Rows.drop(rows, &(&1 == "id"))
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

  describe "blank?/2" do
    @row %{"id" => "1", "name" => "", "note" => nil, "tag" => "  "}

    test "true when the column is nil, empty or whitespace" do
      assert Rows.blank?(@row, "name")
      assert Rows.blank?(@row, "note")
      assert Rows.blank?(@row, "tag")
    end

    test "false when the column has a value" do
      refute Rows.blank?(@row, "id")
    end

    test "several columns are blank only when all of them are" do
      assert Rows.blank?(@row, ["name", "note"])
      refute Rows.blank?(@row, ["name", "id"])
    end

    test "other columns do not matter" do
      assert Rows.blank?(%{"a" => "x", "b" => ""}, "b")
    end

    test "values that are not strings count as values" do
      refute Rows.blank?(%{"a" => 0}, "a")
    end

    test "unknown column raises, so a typo can never silently keep a row" do
      assert_raise KeyError, fn -> Rows.blank?(@row, "nmae") end
    end

    test "drops rows missing a value with Stream.reject" do
      rows = [%{"id" => "1"}, %{"id" => ""}, %{"id" => nil}, %{"id" => "2"}]

      assert rows |> Stream.reject(&Rows.blank?(&1, "id")) |> Enum.map(& &1["id"]) == ["1", "2"]
    end
  end

  describe "reject_blank/2" do
    @padded [
      %{"id" => "1", "name" => "alice"},
      %{"id" => "", "name" => "  "},
      %{"id" => "2", "name" => ""},
      %{"id" => nil, "name" => nil}
    ]

    test "drops rows that are blank in every column" do
      assert @padded |> Rows.reject_blank() |> Enum.map(& &1["id"]) == ["1", "2"]
    end

    test "drops rows that are blank in the named column" do
      assert @padded |> Rows.reject_blank("name") |> Enum.map(& &1["id"]) == ["1"]
    end

    test "drops rows that are blank in all of several columns" do
      assert @padded |> Rows.reject_blank(["id", "name"]) |> Enum.map(& &1["id"]) == ["1", "2"]
    end

    test "unknown column raises" do
      assert_raise KeyError, fn -> @padded |> Rows.reject_blank("nmae") |> Enum.to_list() end
    end

    test "is lazy" do
      rows = Stream.map(@padded, fn _ -> raise "read too early" end)

      _stream = Rows.reject_blank(rows)
      _stream = Rows.reject_blank(rows, "id")
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

  describe "distinct/2" do
    @traits [
      %{"id" => "a", "trait" => "weight"},
      %{"id" => "a", "trait" => "teeth"},
      %{"id" => "b", "trait" => ""},
      %{"id" => "b", "trait" => "weight"},
      %{"id" => "c", "trait" => nil},
      %{"id" => "d", "trait" => ""}
    ]

    test "keeps the first row for each value, in order" do
      assert @traits |> Rows.distinct("trait") |> Enum.map(& &1["id"]) == ["a", "a", "b", "c"]
    end

    test "returns whole rows" do
      assert @traits |> Rows.distinct("trait") |> Enum.take(1) == [
               %{"id" => "a", "trait" => "weight"}
             ]
    end

    test "blank values count as values" do
      assert @traits |> Rows.distinct("trait") |> Enum.map(& &1["trait"]) ==
               ["weight", "teeth", "", nil]
    end

    test "blanks can be rejected first" do
      assert @traits
             |> Rows.reject_blank("trait")
             |> Rows.distinct("trait")
             |> Enum.map(& &1["trait"]) == ["weight", "teeth"]
    end

    test "values that are not strings are kept apart from their text" do
      rows = [%{"n" => 1}, %{"n" => "1"}, %{"n" => 1}]

      assert rows |> Rows.distinct("n") |> Enum.to_list() == [%{"n" => 1}, %{"n" => "1"}]
    end

    test "unknown column raises" do
      assert_raise KeyError, fn -> @traits |> Rows.distinct("tarit") |> Enum.to_list() end
    end

    test "no rows gives no rows" do
      assert [] |> Rows.distinct("trait") |> Enum.to_list() == []
    end

    test "is lazy" do
      rows = Stream.map(@traits, fn _ -> raise "read too early" end)

      _stream = Rows.distinct(rows, "trait")
    end
  end

  describe "fill_down/2" do
    @sparse [
      %{"id" => "a", "kind" => "x", "n" => "1"},
      %{"id" => "", "kind" => nil, "n" => "2"},
      %{"id" => "  ", "kind" => "y", "n" => "3"},
      %{"id" => "b", "kind" => "", "n" => "4"}
    ]

    test "a blank cell takes the last value above it" do
      assert @sparse |> Rows.fill_down("id") |> Enum.map(& &1["id"]) == ["a", "a", "a", "b"]
    end

    test "fills several columns independently" do
      assert @sparse |> Rows.fill_down(["id", "kind"]) |> Enum.map(&{&1["id"], &1["kind"]}) == [
               {"a", "x"},
               {"a", "x"},
               {"a", "y"},
               {"b", "y"}
             ]
    end

    test "other columns are untouched" do
      assert @sparse |> Rows.fill_down("id") |> Enum.map(& &1["n"]) == ["1", "2", "3", "4"]
    end

    test "blanks before the first value stay blank" do
      rows = [%{"id" => ""}, %{"id" => nil}, %{"id" => "a"}, %{"id" => ""}]

      assert rows |> Rows.fill_down("id") |> Enum.map(& &1["id"]) == ["", nil, "a", "a"]
    end

    test "values that are not strings are carried too" do
      rows = [%{"id" => 7}, %{"id" => nil}]

      assert rows |> Rows.fill_down("id") |> Enum.map(& &1["id"]) == [7, 7]
    end

    test "unknown column raises" do
      assert_raise KeyError, fn -> @sparse |> Rows.fill_down("di") |> Enum.to_list() end
    end

    test "no rows gives no rows" do
      assert [] |> Rows.fill_down("id") |> Enum.to_list() == []
    end

    test "is lazy" do
      rows = Stream.map(@sparse, fn _ -> raise "read too early" end)

      _stream = Rows.fill_down(rows, "id")
    end
  end

  describe "group/2" do
    @lines [
      %{"id" => "i-1", "kg" => "2", "seen" => "2026"},
      %{"id" => "i-1", "kg" => "3", "seen" => "2027"},
      %{"id" => "i-2", "kg" => "5", "seen" => "2026"}
    ]

    defp total(lines),
      do: %{"kg" => lines |> Enum.map(&String.to_integer(&1["kg"])) |> Enum.sum()}

    test "folds the lines of each id into one row with the function" do
      assert @lines |> Rows.group(by: "id", into: &total/1) |> Enum.to_list() == [
               %{"id" => "i-1", "kg" => 5},
               %{"id" => "i-2", "kg" => 5}
             ]
    end

    test "the function is given every line of the id in order" do
      assert @lines
             |> Rows.group(by: "id", into: &%{"seen" => Enum.map(&1, fn l -> l["seen"] end)})
             |> Enum.to_list() == [
               %{"id" => "i-1", "seen" => ["2026", "2027"]},
               %{"id" => "i-2", "seen" => ["2026"]}
             ]
    end

    test "the by column is always on the row, even if the function drops it" do
      assert [row | _] = @lines |> Rows.group(by: "id", into: fn _ -> %{} end) |> Enum.to_list()

      assert row == %{"id" => "i-1"}
    end

    test "only neighbouring lines are grouped, like pivot" do
      lines = [%{"id" => "a"}, %{"id" => "b"}, %{"id" => "a"}]

      assert lines |> Rows.group(by: "id", into: &%{"n" => length(&1)}) |> Enum.map(& &1["id"]) ==
               ["a", "b", "a"]
    end

    test "unknown by column raises" do
      assert_raise KeyError, fn ->
        @lines |> Rows.group(by: "di", into: &total/1) |> Enum.to_list()
      end
    end

    test "a function that does not return a row raises" do
      assert_raise ArgumentError, ~r/i-1/, fn ->
        @lines |> Rows.group(by: "id", into: fn _ -> :nope end) |> Enum.to_list()
      end
    end

    test "into must be a function of the lines" do
      assert_raise ArgumentError, fn -> Rows.group(@lines, by: "id", into: &Map.get/2) end
    end

    test "an unknown option raises" do
      assert_raise ArgumentError, fn -> Rows.group(@lines, by: "id", into: &total/1, with: 1) end
    end

    test "a missing option raises" do
      assert_raise KeyError, fn -> Rows.group(@lines, by: "id") end
    end

    test "no lines gives no rows" do
      assert [] |> Rows.group(by: "id", into: &total/1) |> Enum.to_list() == []
    end

    test "is lazy" do
      rows = Stream.map(@lines, fn _ -> raise "read too early" end)

      _stream = Rows.group(rows, by: "id", into: &total/1)
    end
  end

  describe "pivot/2" do
    @opts [by: "id", key: "key", value: "value", columns: ["name", "type", "owner"]]

    @long [
      %{"id" => "i-1", "key" => "name", "value" => "web"},
      %{"id" => "i-1", "key" => "type", "value" => "t3"},
      %{"id" => "i-1", "key" => "owner", "value" => "bob"},
      %{"id" => "i-2", "key" => "name", "value" => "db"},
      %{"id" => "i-2", "key" => "type", "value" => "m5"},
      %{"id" => "i-2", "key" => "owner", "value" => "amy"}
    ]

    test "turns the lines of each id into one row" do
      assert @long |> Rows.pivot(@opts) |> Enum.to_list() == [
               %{"id" => "i-1", "name" => "web", "type" => "t3", "owner" => "bob"},
               %{"id" => "i-2", "name" => "db", "type" => "m5", "owner" => "amy"}
             ]
    end

    test "ids can have any number of lines and a missing key is nil" do
      long = [
        %{"id" => "i-1", "key" => "name", "value" => "web"},
        %{"id" => "i-2", "key" => "owner", "value" => "amy"},
        %{"id" => "i-2", "key" => "name", "value" => "db"}
      ]

      assert long |> Rows.pivot(@opts) |> Enum.to_list() == [
               %{"id" => "i-1", "name" => "web", "type" => nil, "owner" => nil},
               %{"id" => "i-2", "name" => "db", "type" => nil, "owner" => "amy"}
             ]
    end

    test "other columns on the lines are dropped" do
      long = [%{"id" => "i-1", "key" => "name", "value" => "web", "seen" => "2026"}]

      assert [row] = long |> Rows.pivot(@opts) |> Enum.to_list()
      refute Map.has_key?(row, "seen")
    end

    test "a key twice for one id raises" do
      long = [
        %{"id" => "i-1", "key" => "name", "value" => "web"},
        %{"id" => "i-1", "key" => "name", "value" => "api"}
      ]

      assert_raise ArgumentError, ~r/name/, fn -> long |> Rows.pivot(@opts) |> Enum.to_list() end
    end

    test "a key not in columns raises" do
      long = [%{"id" => "i-1", "key" => "region", "value" => "us-east"}]

      assert_raise ArgumentError, ~r/region/, fn ->
        long |> Rows.pivot(@opts) |> Enum.to_list()
      end
    end

    test "a missing option raises" do
      assert_raise KeyError, fn -> Rows.pivot(@long, Keyword.delete(@opts, :columns)) end
    end

    test "an unknown option raises" do
      assert_raise ArgumentError, fn -> Rows.pivot(@long, [{:colums, []} | @opts]) end
    end

    test "no lines gives no rows" do
      assert [] |> Rows.pivot(@opts) |> Enum.to_list() == []
    end

    test "is lazy" do
      rows = Stream.map(@long, fn _ -> raise "read too early" end)

      _stream = Rows.pivot(rows, @opts)
    end
  end

  describe "parallel/3" do
    defp numbered(n), do: for(i <- 1..n, do: %{"id" => "#{i}", "name" => "n#{i}"})

    defp upcase(chunk), do: Rows.update(chunk, "name", &String.upcase/1)

    test "gives the same rows in the same order as running the pipeline in sequence" do
      rows = numbered(2_500)

      assert rows |> Rows.parallel(&upcase/1, chunk: 100) |> Enum.to_list() ==
               rows |> upcase() |> Enum.to_list()
    end

    test "the function gets chunks of rows" do
      sizes =
        numbered(250)
        |> Rows.parallel(fn chunk -> [%{"size" => Enum.count(chunk)}] end, chunk: 100)
        |> Enum.map(& &1["size"])

      assert sizes == [100, 100, 50]
    end

    test "keyed privacy output is the same in parallel" do
      keyring = Refract.Privacy.Keyring.new!(keys: %{1 => :binary.copy(<<1>>, 32)})
      rows = for i <- 1..500, do: %{"eid" => Integer.to_string(982_000_000_000_000 + i)}

      pseudonymise =
        &Rows.update(&1, "eid", fn eid -> Refract.Privacy.Pseudonym.apply!(eid, :eid, keyring) end)

      assert rows |> Rows.parallel(pseudonymise, chunk: 50) |> Enum.to_list() ==
               rows |> pseudonymise.() |> Enum.to_list()
    end

    test "is lazy" do
      rows = Stream.map(@rows, fn _ -> raise "read too early" end)

      _stream = Rows.parallel(rows, &upcase/1)
    end

    test "a raise in a chunk reaches the caller as the same exception" do
      assert_raise RuntimeError, "boom", fn ->
        numbered(10) |> Rows.parallel(fn _chunk -> raise "boom" end) |> Enum.to_list()
      end
    end

    test "chunk and max_concurrency must be positive integers" do
      for bad <- [0, -1, 1.5] do
        assert_raise ArgumentError, fn -> Rows.parallel(@rows, &upcase/1, chunk: bad) end

        assert_raise ArgumentError, fn ->
          Rows.parallel(@rows, &upcase/1, max_concurrency: bad)
        end
      end
    end

    test "unknown option raises" do
      assert_raise ArgumentError, fn -> Rows.parallel(@rows, &upcase/1, chunks: 10) end
    end
  end
end
