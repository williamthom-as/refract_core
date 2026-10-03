defmodule Refract.CleanTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  alias Refract.Clean

  describe "normalise_whitespace/1" do
    test "collapses runs inside and trims the ends" do
      assert Clean.normalise_whitespace("  big   red\tapple  ") == "big red apple"
    end

    test "line breaks become one space" do
      assert Clean.normalise_whitespace("unit 4\r\n12 high st\nsydney") ==
               "unit 4 12 high st sydney"
    end

    test "non breaking spaces count as whitespace" do
      assert Clean.normalise_whitespace("1\u00a0000\u00a0\u00a0kg") == "1 000 kg"
    end

    test "blank becomes empty" do
      assert Clean.normalise_whitespace(" \t\n ") == ""
    end

    test "values that are not strings pass through" do
      for value <- [nil, 7, ~D[2026-10-02]] do
        assert Clean.normalise_whitespace(value) == value
      end
    end
  end

  describe "strip_control_characters/1" do
    test "removes control characters" do
      assert Clean.strip_control_characters("ab\u0000c\u0007d\u007f") == "abcd"
    end

    test "removes zero width characters" do
      assert Clean.strip_control_characters("\ufeffap\u200bple\u200d") == "apple"
    end

    test "keeps tabs and line breaks" do
      assert Clean.strip_control_characters("a\tb\nc\r\n") == "a\tb\nc\r\n"
    end

    test "keeps ordinary text and accents" do
      assert Clean.strip_control_characters("café 12-b") == "café 12-b"
    end

    test "values that are not strings pass through" do
      for value <- [nil, 7, ~D[2026-10-02]] do
        assert Clean.strip_control_characters(value) == value
      end
    end
  end
end
