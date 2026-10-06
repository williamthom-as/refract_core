defmodule Refract.ParseTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  alias Refract.Parse

  defp ok(string), do: {:ok, Decimal.new(string)}

  describe "number/2" do
    test "parses a decimal string exactly" do
      assert Parse.number("1.24") == ok("1.24")
    end

    test "parses integers and negatives" do
      assert Parse.number("12") == ok("12")
      assert Parse.number("-0.5") == ok("-0.5")
    end

    test "trims surrounding whitespace" do
      assert Parse.number("  3.5 \n") == ok("3.5")
    end

    test "comma thousands by default" do
      assert Parse.number("1,234.56") == ok("1234.56")
    end

    test "locale de swaps the separators" do
      assert Parse.number("1.234,56", locale: :de) == ok("1234.56")
      assert Parse.number("0,5", locale: :de) == ok("0.5")
    end

    test "native numbers become decimals" do
      assert Parse.number(7) == ok("7")
      assert Parse.number(1.24) == ok("1.24")
      assert Parse.number(Decimal.new("9.9")) == ok("9.9")
    end

    test "text that is not a number is an error" do
      assert Parse.number("12abc") == {:error, {:not_a_number, "12abc"}}
      assert Parse.number("thirty") == {:error, {:not_a_number, "thirty"}}
    end

    test "blank and nil are errors" do
      assert Parse.number("") == {:error, {:not_a_number, ""}}
      assert Parse.number("  ") == {:error, {:not_a_number, "  "}}
      assert Parse.number(nil) == {:error, {:not_a_number, nil}}
    end

    test "numbers past decimal128 are errors rather than a hang" do
      assert Parse.number("1e1000000000") == {:error, {:not_a_number, "1e1000000000"}}

      assert Parse.number("12345678901234567890123456789012345") ==
               {:error, {:not_a_number, "12345678901234567890123456789012345"}}

      assert {:ok, _} = Parse.number("1234567890123456789012345678901234")
    end

    test "unknown locale raises" do
      assert_raise ArgumentError, fn -> Parse.number("1", locale: :xx) end
    end

    test "unknown option raises" do
      assert_raise ArgumentError, fn -> Parse.number("1", locle: :de) end
    end
  end

  describe "number!/2" do
    test "returns the decimal" do
      assert Parse.number!("1.24") == Decimal.new("1.24")
    end

    test "raises on text that is not a number" do
      assert_raise ArgumentError, ~r/thirty/, fn -> Parse.number!("thirty") end
    end

    test "passes options through" do
      assert Parse.number!("1.234,56", locale: :de) == Decimal.new("1234.56")
    end
  end

  describe "integer/2" do
    test "parses whole numbers and negatives" do
      assert Parse.integer("12") == {:ok, 12}
      assert Parse.integer("-3") == {:ok, -3}
    end

    test "trims surrounding whitespace" do
      assert Parse.integer(" 12 \n") == {:ok, 12}
    end

    test "native integers pass" do
      assert Parse.integer(7) == {:ok, 7}
    end

    test "anything else is an error" do
      for value <- ["1.5", "12a", "1,234", "", nil, 1.5, Decimal.new("3")] do
        assert Parse.integer(value) == {:error, {:not_an_integer, value}}, inspect(value)
      end
    end

    test "unknown option raises" do
      assert_raise ArgumentError, fn -> Parse.integer("1", base: 16) end
    end
  end

  describe "integer!/2" do
    test "returns the integer" do
      assert Parse.integer!("12") == 12
    end

    test "raises on anything else" do
      assert_raise ArgumentError, ~r/12a/, fn -> Parse.integer!("12a") end
    end
  end

  describe "date/2" do
    test "parses iso dates" do
      assert Parse.date("2026-10-02") == {:ok, ~D[2026-10-02]}
    end

    test "iso date times keep the date" do
      assert Parse.date("2026-10-02T09:30:00Z") == {:ok, ~D[2026-10-02]}
      assert Parse.date("2026-10-02T09:30:00") == {:ok, ~D[2026-10-02]}
    end

    test "a time after any format keeps the date" do
      assert Parse.date("2026-10-02 09:30:00") == {:ok, ~D[2026-10-02]}
      assert Parse.date("2026/10/02 09:30:00") == {:ok, ~D[2026-10-02]}
      assert Parse.date("2/10/2026 9:30", formats: [:dmy]) == {:ok, ~D[2026-10-02]}
      assert Parse.date("02 Oct 2026 9:30", formats: ["dd MMM yyyy"]) == {:ok, ~D[2026-10-02]}
    end

    test "text after the date that is not a time is an error" do
      assert Parse.date("2026-10-02 noon") == {:error, {:not_a_date, "2026-10-02 noon"}}
      assert Parse.date("2026-10-02 25:00") == {:error, {:not_a_date, "2026-10-02 25:00"}}
    end

    test "year first with slash or dot by default" do
      assert Parse.date("2026/10/02") == {:ok, ~D[2026-10-02]}
      assert Parse.date("2026.10.02") == {:ok, ~D[2026-10-02]}
    end

    test "trims surrounding whitespace" do
      assert Parse.date(" 2026-10-02\n") == {:ok, ~D[2026-10-02]}
    end

    test "day or month first is never guessed by default" do
      assert Parse.date("02/10/2026") == {:error, {:not_a_date, "02/10/2026"}}
    end

    test "dmy and mdy when asked for" do
      assert Parse.date("02/10/2026", formats: [:dmy]) == {:ok, ~D[2026-10-02]}
      assert Parse.date("02/10/2026", formats: [:mdy]) == {:ok, ~D[2026-02-10]}
    end

    test "dash and dot separators and single digit parts" do
      assert Parse.date("2-10-2026", formats: [:dmy]) == {:ok, ~D[2026-10-02]}
      assert Parse.date("2.1.2026", formats: [:dmy]) == {:ok, ~D[2026-01-02]}
    end

    test "formats are tried in order and the first that parses wins" do
      assert Parse.date("02/10/2026", formats: [:dmy, :mdy]) == {:ok, ~D[2026-10-02]}
      assert Parse.date("31/12/2026", formats: [:mdy, :dmy]) == {:ok, ~D[2026-12-31]}
    end

    test "impossible dates are errors" do
      assert Parse.date("2026-02-30") == {:error, {:not_a_date, "2026-02-30"}}
    end

    test "two digit years are errors" do
      assert Parse.date("02/10/26", formats: [:dmy]) == {:error, {:not_a_date, "02/10/26"}}
    end

    test "native dates pass and date times keep the date" do
      assert Parse.date(~D[2026-10-02]) == {:ok, ~D[2026-10-02]}
      assert Parse.date(~N[2026-10-02 09:30:00]) == {:ok, ~D[2026-10-02]}
      assert Parse.date(~U[2026-10-02 09:30:00Z]) == {:ok, ~D[2026-10-02]}
    end

    test "text, blank and nil are errors" do
      assert Parse.date("soon") == {:error, {:not_a_date, "soon"}}
      assert Parse.date("") == {:error, {:not_a_date, ""}}
      assert Parse.date(nil) == {:error, {:not_a_date, nil}}
    end

    test "unknown format raises" do
      assert_raise ArgumentError, fn -> Parse.date("2026-10-02", formats: [:ydm]) end
    end

    test "unknown option raises" do
      assert_raise ArgumentError, fn -> Parse.date("2026-10-02", fromats: [:dmy]) end
    end
  end

  describe "date/2 with patterns" do
    test "a fixed shape with a month name" do
      assert Parse.date("02-Oct-2026", formats: ["dd-MMM-yyyy"]) == {:ok, ~D[2026-10-02]}
    end

    test "d and M take one or two digits" do
      assert Parse.date("2-Oct-2026", formats: ["d-MMM-yyyy"]) == {:ok, ~D[2026-10-02]}
      assert Parse.date("2/1/2026", formats: ["d/M/yyyy"]) == {:ok, ~D[2026-01-02]}
      assert Parse.date("12/11/2026", formats: ["d/M/yyyy"]) == {:ok, ~D[2026-11-12]}
    end

    test "dd and MM need exactly two digits" do
      assert Parse.date("2-Oct-2026", formats: ["dd-MMM-yyyy"]) ==
               {:error, {:not_a_date, "2-Oct-2026"}}

      assert Parse.date("02/1/2026", formats: ["dd/MM/yyyy"]) ==
               {:error, {:not_a_date, "02/1/2026"}}
    end

    test "year first" do
      assert Parse.date("2026/10/02", formats: ["yyyy/MM/dd"]) == {:ok, ~D[2026-10-02]}
    end

    test "month names in any case" do
      assert Parse.date("2 OCT 2026", formats: ["d MMM yyyy"]) == {:ok, ~D[2026-10-02]}
      assert Parse.date("2 oct 2026", formats: ["d MMM yyyy"]) == {:ok, ~D[2026-10-02]}
    end

    test "unknown month names are errors" do
      assert Parse.date("2 Okt 2026", formats: ["d MMM yyyy"]) ==
               {:error, {:not_a_date, "2 Okt 2026"}}
    end

    test "patterns and named formats are tried in order" do
      formats = ["dd.MM.yyyy", :iso]

      assert Parse.date("02.10.2026", formats: formats) == {:ok, ~D[2026-10-02]}
      assert Parse.date("2026-10-02", formats: formats) == {:ok, ~D[2026-10-02]}
    end

    test "literals must match" do
      assert Parse.date("02/10/2026", formats: ["dd-MM-yyyy"]) ==
               {:error, {:not_a_date, "02/10/2026"}}
    end

    test "text left over is an error" do
      assert Parse.date("02-10-2026 x", formats: ["dd-MM-yyyy"]) ==
               {:error, {:not_a_date, "02-10-2026 x"}}
    end

    test "year needs four digits" do
      assert Parse.date("02-10-26", formats: ["dd-MM-yyyy"]) ==
               {:error, {:not_a_date, "02-10-26"}}
    end

    test "impossible dates are errors" do
      assert Parse.date("30-Feb-2026", formats: ["d-MMM-yyyy"]) ==
               {:error, {:not_a_date, "30-Feb-2026"}}
    end

    test "unknown letters raise and name them" do
      assert_raise ArgumentError, ~r/"DD"/, fn ->
        Parse.date("02-10-2026", formats: ["DD-m-Y"])
      end
    end

    test "unsupported lengths raise" do
      assert_raise ArgumentError, ~r/"yy"/, fn ->
        Parse.date("02/10/26", formats: ["dd/MM/yy"])
      end
    end

    test "a pattern needs day, month and year" do
      assert_raise ArgumentError, fn -> Parse.date("02/10", formats: ["dd/MM"]) end
      assert_raise ArgumentError, fn -> Parse.date("02/02/2026", formats: ["dd/dd/yyyy"]) end
    end

    test "a bad pattern raises whatever the value" do
      assert_raise ArgumentError, fn -> Parse.date(nil, formats: ["DD"]) end
      assert_raise ArgumentError, fn -> Parse.date(~D[2026-10-02], formats: ["DD"]) end
    end
  end

  describe "date!/2" do
    test "returns the date" do
      assert Parse.date!("02/10/2026", formats: [:dmy]) == ~D[2026-10-02]
    end

    test "raises on text that is not a date" do
      assert_raise ArgumentError, ~r/soon/, fn -> Parse.date!("soon") end
    end
  end

  describe "datetime/2" do
    test "parses iso date times" do
      assert Parse.datetime("2026-10-02T09:30:00") == {:ok, ~N[2026-10-02 09:30:00]}
      assert Parse.datetime("2026-10-02 09:30:00") == {:ok, ~N[2026-10-02 09:30:00]}
    end

    test "offsets and fractions are dropped" do
      assert Parse.datetime("2026-10-02T09:30:00Z") == {:ok, ~N[2026-10-02 09:30:00]}
      assert Parse.datetime("2026-10-02T09:30:00.123+10:00") == {:ok, ~N[2026-10-02 09:30:00]}
    end

    test "year first with slash by default" do
      assert Parse.datetime("2026/10/02 05:29:25") == {:ok, ~N[2026-10-02 05:29:25]}
    end

    test "seconds are optional and the hour can be one digit" do
      assert Parse.datetime("2026/10/02 9:30") == {:ok, ~N[2026-10-02 09:30:00]}
    end

    test "trims surrounding whitespace" do
      assert Parse.datetime(" 2026-10-02 09:30:00\n") == {:ok, ~N[2026-10-02 09:30:00]}
    end

    test "day or month first is never guessed by default" do
      assert Parse.datetime("02/10/2026 9:30") ==
               {:error, {:not_a_datetime, "02/10/2026 9:30"}}
    end

    test "dmy and mdy and patterns when asked for" do
      assert Parse.datetime("2/10/2026 9:30", formats: [:dmy]) == {:ok, ~N[2026-10-02 09:30:00]}
      assert Parse.datetime("2/10/2026 9:30", formats: [:mdy]) == {:ok, ~N[2026-02-10 09:30:00]}

      assert Parse.datetime("02 Oct 2026 9:30", formats: ["dd MMM yyyy"]) ==
               {:ok, ~N[2026-10-02 09:30:00]}
    end

    test "a date without a time is an error" do
      assert Parse.datetime("2026-10-02") == {:error, {:not_a_datetime, "2026-10-02"}}
      assert Parse.datetime(~D[2026-10-02]) == {:error, {:not_a_datetime, ~D[2026-10-02]}}
    end

    test "impossible dates and times are errors" do
      assert Parse.datetime("2026-02-30 09:30") == {:error, {:not_a_datetime, "2026-02-30 09:30"}}
      assert Parse.datetime("2026-10-02 24:00") == {:error, {:not_a_datetime, "2026-10-02 24:00"}}
      assert Parse.datetime("2026-10-02 09:60") == {:error, {:not_a_datetime, "2026-10-02 09:60"}}
    end

    test "native date times pass and utc date times drop the zone" do
      assert Parse.datetime(~N[2026-10-02 09:30:00]) == {:ok, ~N[2026-10-02 09:30:00]}
      assert Parse.datetime(~U[2026-10-02 09:30:00Z]) == {:ok, ~N[2026-10-02 09:30:00]}
    end

    test "text, blank and nil are errors" do
      assert Parse.datetime("soon") == {:error, {:not_a_datetime, "soon"}}
      assert Parse.datetime("") == {:error, {:not_a_datetime, ""}}
      assert Parse.datetime(nil) == {:error, {:not_a_datetime, nil}}
    end

    test "unknown format raises" do
      assert_raise ArgumentError, fn -> Parse.datetime("2026-10-02 09:30", formats: [:ydm]) end
    end

    test "unknown option raises" do
      assert_raise ArgumentError, fn -> Parse.datetime("2026-10-02 09:30", fromats: [:dmy]) end
    end
  end

  describe "datetime!/2" do
    test "returns the naive date time" do
      assert Parse.datetime!("02/10/2026 9:30", formats: [:dmy]) == ~N[2026-10-02 09:30:00]
    end

    test "raises on text that is not a datetime" do
      assert_raise ArgumentError, ~r/soon/, fn -> Parse.datetime!("soon") end
    end
  end

  describe "boolean/1" do
    test "true words in any case" do
      for word <- ["true", "TRUE", "yes", "Yes", "y", "Y", "1", " true "] do
        assert Parse.boolean(word) == {:ok, true}, word
      end
    end

    test "false words in any case" do
      for word <- ["false", "False", "no", "NO", "n", "N", "0"] do
        assert Parse.boolean(word) == {:ok, false}, word
      end
    end

    test "native booleans pass" do
      assert Parse.boolean(true) == {:ok, true}
      assert Parse.boolean(false) == {:ok, false}
    end

    test "native 1 and 0 pass" do
      assert Parse.boolean(1) == {:ok, true}
      assert Parse.boolean(0) == {:ok, false}
    end

    test "anything else is an error" do
      for value <- ["maybe", "2", "", nil, 2] do
        assert Parse.boolean(value) == {:error, {:not_a_boolean, value}}, inspect(value)
      end
    end
  end

  describe "boolean!/1" do
    test "returns the boolean" do
      assert Parse.boolean!("yes") == true
    end

    test "raises on anything else" do
      assert_raise ArgumentError, ~r/maybe/, fn -> Parse.boolean!("maybe") end
    end
  end
end
