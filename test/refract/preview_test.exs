defmodule Refract.PreviewTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  @moduletag timeout: 5_000

  alias Refract.Preview

  @rows [
    %{"id" => "1", "name" => "alice"},
    %{"id" => "2", "name" => "bob"},
    %{"id" => "3", "name" => "carol"}
  ]

  defp print(rows, opts \\ []), do: capture_io(fn -> assert :ok = Preview.print(rows, opts) end)

  test "prints rows as a table with the header first" do
    assert print(@rows) == """
           +----+-------+
           | id | name  |
           +----+-------+
           | 1  | alice |
           | 2  | bob   |
           | 3  | carol |
           +----+-------+
           """
  end

  test "title goes above the table" do
    assert print(Enum.take(@rows, 1), title: "people") == """
           people
           +----+-------+
           | id | name  |
           +----+-------+
           | 1  | alice |
           +----+-------+
           """
  end

  test "limit shows the first rows and says more were not shown" do
    assert print(@rows, limit: 2) == """
           +----+-------+
           | id | name  |
           +----+-------+
           | 1  | alice |
           | 2  | bob   |
           +----+-------+
           first 2 rows shown, more not shown
           """
  end

  test "exactly limit rows says nothing more" do
    refute print(@rows, limit: 3) =~ "not shown"
  end

  test "header picks the columns and their order" do
    assert print(Enum.take(@rows, 1), header: ["name", "id"]) == """
           +-------+----+
           | name  | id |
           +-------+----+
           | alice | 1  |
           +-------+----+
           """
  end

  test "cells that are not strings print readably and nil prints empty" do
    rows = [%{"d" => ~D[2026-10-02], "n" => Decimal.new("1.24"), "i" => 7, "x" => nil}]

    assert print(rows) == """
           +------------+---+------+---+
           | d          | i | n    | x |
           +------------+---+------+---+
           | 2026-10-02 | 7 | 1.24 |   |
           +------------+---+------+---+
           """
  end

  test "widths count characters not bytes" do
    assert print([%{"name" => "café"}]) == """
           +------+
           | name |
           +------+
           | café |
           +------+
           """
  end

  test "long cells are cut to 30 characters" do
    long = String.duplicate("x", 40)

    output = print([%{"note" => long}])

    assert output =~ "| " <> String.duplicate("x", 27) <> "... |"
    refute output =~ String.duplicate("x", 28)
  end

  test "no rows says so" do
    assert print([], title: "people") == "people\nno rows\n"
  end

  test "reads only the rows it needs" do
    rows = Stream.concat(@rows, Stream.map([%{}], fn _ -> raise "read too far" end))

    assert print(rows, limit: 2) =~ "more not shown"
  end

  test "limit must be a positive integer" do
    for bad <- [0, -1, "2"] do
      assert_raise ArgumentError, fn -> Preview.print(@rows, limit: bad) end
    end
  end

  test "unknown option raises" do
    assert_raise ArgumentError, fn -> Preview.print(@rows, limt: 2) end
  end
end
