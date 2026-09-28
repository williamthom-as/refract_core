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

    test "is lazy" do
      rows = Stream.map(@rows, fn _ -> raise "read too early" end)

      assert %Stream{} = Rows.take(rows, ["id"])
    end
  end
end
