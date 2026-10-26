defmodule Refract.ParseIsoTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  @moduletag timeout: 20_000

  alias Refract.Parse

  defp pad(number, width), do: number |> Integer.to_string() |> String.pad_leading(width, "0")

  defp date_string(year, month, day), do: "#{pad(year, 4)}-#{pad(month, 2)}-#{pad(day, 2)}"

  defp time_string(hour, minute, second),
    do: "#{pad(hour, 2)}:#{pad(minute, 2)}:#{pad(second, 2)}"

  describe "iso shapes give what their parts say" do
    property "date times with T or a space, with or without Z" do
      check all(
              year <- integer(1..9999),
              month <- integer(1..12),
              day <- integer(1..28),
              hour <- integer(0..23),
              minute <- integer(0..59),
              second <- integer(0..59),
              separator <- member_of(["T", " "]),
              zone <- member_of(["", "Z"])
            ) do
        string =
          date_string(year, month, day) <> separator <> time_string(hour, minute, second) <> zone

        naive = NaiveDateTime.new!(year, month, day, hour, minute, second)

        assert Parse.datetime(string) == {:ok, naive}
        assert Parse.date(string) == {:ok, NaiveDateTime.to_date(naive)}
      end
    end

    property "a day past the end of its month is an error, as Date.new says" do
      check all(
              year <- integer(1..9999),
              month <- integer(1..12),
              day <- integer(29..31)
            ) do
        string = date_string(year, month, day)

        expected =
          case Date.new(year, month, day) do
            {:ok, date} -> {:ok, date}
            {:error, _reason} -> {:error, {:not_a_date, string}}
          end

        assert Parse.date(string) == expected
      end
    end
  end

  describe "iso edges stay as they are" do
    test "a comma before the fraction is an error" do
      assert Parse.datetime("2026-10-02T09:30:00,5") ==
               {:error, {:not_a_datetime, "2026-10-02T09:30:00,5"}}
    end

    test "an offset of hours only is an error" do
      assert Parse.datetime("2026-10-02T09:30:00+10", offset: :utc) ==
               {:error, {:not_a_datetime, "2026-10-02T09:30:00+10"}}
    end

    test "an offset is never dropped" do
      assert Parse.datetime("2026-10-02T09:30:00+10:00") ==
               {:error, {:has_offset, "2026-10-02T09:30:00+10:00"}}

      assert Parse.datetime("2026-10-02T09:30:00+10:00", offset: :utc) ==
               {:ok, ~N[2026-10-01 23:30:00]}
    end

    test "lower case t and z, and the basic format, are errors" do
      for string <- ["2026-10-02t09:30:00", "2026-10-02T09:30:00z", "20261002T093000"] do
        assert Parse.datetime(string) == {:error, {:not_a_datetime, string}}
      end

      assert Parse.date("20261002") == {:error, {:not_a_date, "20261002"}}
    end

    test "impossible dates and times in the iso shape are errors" do
      for string <- ["2026-02-30T09:30:00", "2026-10-02T24:00:00", "2026-10-02T23:59:60"] do
        assert Parse.datetime(string) == {:error, {:not_a_datetime, string}}
      end
    end

    test "negative years parse" do
      assert Parse.datetime("-2026-10-02T09:30:00") == {:ok, ~N[-2026-10-02 09:30:00]}
    end

    test "surrounding whitespace is trimmed" do
      assert Parse.datetime(" 2026-10-02T09:30:00Z\n") == {:ok, ~N[2026-10-02 09:30:00]}
      assert Parse.date(" 2026-10-02 ") == {:ok, ~D[2026-10-02]}
    end
  end

  describe "formats are tried in the order given" do
    test "a pattern before :iso wins on an iso looking value" do
      assert Parse.date("2026-10-02", formats: ["yyyy-dd-MM", :iso]) == {:ok, ~D[2026-02-10]}

      assert Parse.datetime("2026-10-02 09:30:00", formats: ["yyyy-dd-MM", :iso]) ==
               {:ok, ~N[2026-02-10 09:30:00]}
    end

    test "without :iso an iso value is not read" do
      assert Parse.date("2026-10-02", formats: [:dmy]) == {:error, {:not_a_date, "2026-10-02"}}

      assert Parse.datetime("2026-10-02T09:30:00", formats: [:dmy]) ==
               {:error, {:not_a_datetime, "2026-10-02T09:30:00"}}
    end
  end
end
