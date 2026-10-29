defmodule Refract.CSV.FormulaTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag timeout: 5_000

  alias Refract.CSV
  alias Refract.Parse

  defp encode(cells, opts \\ []) do
    [%{"a" => cells}]
    |> CSV.encode(Keyword.merge([header: ["a"]], opts))
    |> Enum.join()
    |> String.replace_prefix("a\n", "")
    |> String.replace_suffix("\n", "")
  end

  @starts ["=", "+", "-", "@", "\r", "\n", "\uFF1D", "\uFF0B", "\uFF0D", "\uFF20"]

  describe "escape_formulas (on by default)" do
    test "a cell starting with a formula character gets a tab inside a quoted field" do
      for start <- @starts do
        assert encode(start <> "1+2") == ~s("\t#{start}1+2")
      end
    end

    test "a number written as text is escaped too" do
      assert encode("-12.50") == ~s("\t-12.50")
      assert encode("+61 2 9876 5432") == ~s("\t+61 2 9876 5432")
    end

    test "text that does not start with one is left alone" do
      assert encode("total=12") == "total=12"
      assert encode("north") == "north"
    end

    test "a cell already starting with a tab is left as it is, quoted" do
      assert encode("\t=1+2") == ~s("\t=1+2")
    end

    test "cells that are not text are left alone" do
      assert encode(-12) == "-12"
      assert encode(Decimal.new("-12.50")) == "-12.50"
    end

    test "header cells are escaped too" do
      assert [%{"=total" => "1"}] |> CSV.encode(header: ["=total"]) |> Enum.join() ==
               ~s("\t=total"\n1\n)
    end

    test "every separator quotes the escaped cell" do
      for separator <- [",", ";", "|", "\t"] do
        assert encode("=1+2", separator: separator) == ~s("\t=1+2")
      end
    end

    test "write and write_chunks escape", %{tmp_dir: dir} do
      path = Path.join(dir, "out.csv")

      assert :ok = CSV.write([%{"a" => "=1+2"}], path, header: ["a"])
      assert File.read!(path) == ~s|a\n"\t=1+2"\n|

      assert {:ok, [part]} =
               CSV.write_chunks([%{"a" => "@SUM(A1)"}], Path.join(dir, "part.csv"),
                 rows_per_file: 5,
                 header: ["a"]
               )

      assert File.read!(part) == ~s|a\n"\t@SUM(A1)"\n|
    end

    test "refract reads an escaped cell back with its tab, a number still parses" do
      path = Path.join(System.tmp_dir!(), "formula_#{System.unique_integer([:positive])}.csv")
      on_exit(fn -> File.rm(path) end)

      :ok = CSV.write([%{"a" => "=1+2", "b" => "-12.50"}], path, header: ["a", "b"])

      assert {:ok, rows} = CSV.stream(path)
      assert [%{"a" => "\t=1+2", "b" => "\t-12.50" = amount}] = Enum.to_list(rows)
      assert Parse.number(amount) == {:ok, Decimal.new("-12.50")}
    end
  end

  describe "escape_formulas: false" do
    test "leaves every cell as it is" do
      assert encode("=1+2", escape_formulas: false) == "=1+2"
      assert encode("-12.50", escape_formulas: false) == "-12.50"
    end

    test "is true or false" do
      assert_raise ArgumentError, ~r/escape_formulas/, fn ->
        encode("x", escape_formulas: :yes)
      end
    end
  end
end
