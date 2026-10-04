defmodule Refract.Privacy.RedactTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  alias Refract.Privacy.Redact

  describe "blank/1" do
    test "anything becomes empty" do
      for value <- ["secret", 1_234, nil] do
        assert Redact.blank(value) == ""
      end
    end
  end

  describe "mask/2" do
    test "masks every character and keeps the length" do
      assert Redact.mask("1234567890") == "**********"
    end

    test "keep_last and keep_first show the ends" do
      assert Redact.mask("1234567890", keep_last: 4) == "******7890"
      assert Redact.mask("1234567890", keep_first: 2) == "12********"
      assert Redact.mask("1234567890", keep_first: 2, keep_last: 2) == "12******90"
    end

    test "char sets the mask character" do
      assert Redact.mask("1234567890", keep_first: 2, char: "#") == "12########"
    end

    test "counts characters not bytes" do
      assert Redact.mask("café", keep_last: 1) == "***é"
    end

    test "keeping as much as the value masks all of it" do
      assert Redact.mask("1234", keep_first: 2, keep_last: 2) == "****"
      assert Redact.mask("12", keep_last: 4) == "**"
    end

    test "numbers are masked as text" do
      assert Redact.mask(1_234_567_890, keep_last: 4) == "******7890"
    end

    test "nil passes through" do
      assert Redact.mask(nil) == nil
    end

    test "char must be one character" do
      for bad <- ["", "**", 1] do
        assert_raise ArgumentError, fn -> Redact.mask("1234", char: bad) end
      end
    end

    test "keep_first and keep_last must be non negative integers" do
      assert_raise ArgumentError, fn -> Redact.mask("1234", keep_last: -1) end
      assert_raise ArgumentError, fn -> Redact.mask("1234", keep_first: 1.5) end
    end

    test "unknown option raises" do
      assert_raise ArgumentError, fn -> Redact.mask("1234", keep: 2) end
    end
  end
end
