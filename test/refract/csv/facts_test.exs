defmodule Refract.CSV.FactsTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  alias Refract.CSV

  @csv Path.expand("../../fixtures/csv", __DIR__)

  defp facts(name, opts \\ []) do
    assert {:ok, facts} = CSV.facts(Path.join(@csv, name), opts)

    facts
  end

  describe "line endings" do
    test "lf" do
      assert %{line_endings: :lf, line_ending_counts: %{lf: 3}} = facts("quoted_newline.csv")
    end

    test "crlf" do
      assert %{line_endings: :crlf, line_ending_counts: %{crlf: 3}} = facts("crlf.csv")
    end

    test "cr only" do
      assert %{line_endings: :cr, line_ending_counts: %{cr: 3}} = facts("cr_only.csv")
    end

    test "mixed with the counts of each" do
      assert %{line_endings: :mixed, line_ending_counts: %{crlf: 2, lf: 1}} =
               facts("mixed_line_endings.csv")
    end

    test "newlines inside quoted fields do not count" do
      assert %{line_ending_counts: counts} = facts("quoted_newline.csv")
      assert counts == %{lf: 3}

      assert %{line_ending_counts: crlf_counts} = facts("quoted_newline_crlf.csv")
      assert crlf_counts == %{crlf: 3}
    end

    test "an empty file has none" do
      assert %{line_endings: :none, line_ending_counts: counts} = facts("empty.csv")
      assert counts == %{}
    end
  end

  describe "trailing newline" do
    test "a file ending in a line ending" do
      assert %{trailing_newline: true} = facts("crlf.csv")
      assert %{trailing_newline: true} = facts("cr_only.csv")
    end

    test "a file ending mid line" do
      assert %{trailing_newline: false} = facts("no_trailing_newline.csv")
    end

    test "an empty file" do
      assert %{trailing_newline: false} = facts("empty.csv")
    end
  end

  describe "bom" do
    test "a utf8 bom is reported" do
      assert %{bom: true} = facts("bom.csv")
      assert %{bom: false} = facts("crlf.csv")
    end
  end

  describe "delimiter" do
    test "comma" do
      assert %{delimiter: ",", delimiter_source: :detected} = facts("crlf.csv")
    end

    test "semicolon with decimal commas and a quoted semicolon" do
      assert %{delimiter: ";", delimiter_source: :detected} = facts("semicolon.csv")
    end

    test "tab with a quoted tab" do
      assert %{delimiter: "\t", delimiter_source: :detected} = facts("tab.tsv")
    end

    test "pipe" do
      assert %{delimiter: "|", delimiter_source: :detected} = facts("pipe.csv")
    end

    test "nothing to detect falls back to comma and says so" do
      assert %{delimiter: ",", delimiter_source: :default} = facts("single_column.csv")
    end

    test "a given separator is reported as given" do
      assert %{delimiter: ";", delimiter_source: :given} = facts("crlf.csv", separator: ";")
    end
  end

  describe "sources" do
    test "a string" do
      assert {:ok, %{line_endings: :lf, trailing_newline: true, delimiter: ","}} =
               CSV.facts({:string, "a,b\n1,2\n"})
    end

    test "a stream cannot tell how it ends" do
      assert {:ok, %{line_endings: :lf, trailing_newline: :unknown}} =
               CSV.facts({:stream, ["a,b\n", "1,2\n"]})
    end

    test "a missing file is an error" do
      assert {:error, :enoent} = CSV.facts(Path.join(@csv, "missing.csv"))
    end

    test "an unsupported source is an error" do
      assert {:error, {:unsupported_source, :bills}} = CSV.facts(:bills)
    end
  end
end
