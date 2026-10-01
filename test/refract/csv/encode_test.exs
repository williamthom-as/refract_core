defmodule Refract.CSV.EncodeTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  @moduletag timeout: 10_000

  defp encode!(rows, opts),
    do: rows |> Refract.CSV.encode(opts) |> Enum.to_list() |> IO.iodata_to_binary()

  describe "encode/2" do
    test "header row first, then one line per row" do
      rows = [%{"id" => "1", "name" => "alice"}, %{"id" => "2", "name" => "bob"}]

      assert encode!(rows, header: ["id", "name"]) == "id,name\n1,alice\n2,bob\n"
    end

    test "header: sets the exact output columns and their order" do
      rows = [%{"id" => "1", "name" => "alice", "secret" => "x"}]

      assert encode!(rows, header: ["name", "id"]) == "name,id\nalice,1\n"
    end

    test "row missing a header column raises, same as Rows" do
      assert_raise KeyError, fn ->
        encode!([%{"id" => "1"}], header: ["id", "name"])
      end
    end

    test "without header: uses the first row keys, sorted" do
      rows = [%{"name" => "alice", "id" => "1"}]

      assert encode!(rows, []) == "id,name\n1,alice\n"
    end

    test "no rows with header: gives just the header line" do
      assert encode!([], header: ["id", "name"]) == "id,name\n"
    end

    test "no rows without header: gives nothing" do
      assert encode!([], []) == ""
    end

    test "quotes cells containing separator, quote or newline" do
      rows = [%{"a" => "x,y", "b" => "say \"hi\"", "c" => "line\nbreak"}]

      assert encode!(rows, header: ["a", "b", "c"]) ==
               "a,b,c\n\"x,y\",\"say \"\"hi\"\"\",\"line\nbreak\"\n"
    end

    test "nil becomes an empty cell, numbers become text" do
      rows = [%{"a" => nil, "b" => 3, "c" => 1.5}]

      assert encode!(rows, header: ["a", "b", "c"]) == "a,b,c\n,3,1.5\n"
    end

    test "is lazy, returns a stream of iodata" do
      rows = Stream.map([%{"id" => "1"}], fn _ -> raise "read too early" end)

      # building the stream must not read the source (source raises if read)
      _stream = Refract.CSV.encode(rows, header: ["id"])
    end
  end

  describe "round trip" do
    property "encode then stream gives back the same rows" do
      header = ["a", "b", "c"]

      check all(
              rows <-
                list_of(fixed_map(Map.new(header, &{&1, string(:printable)})), max_length: 20)
            ) do
        csv = encode!(rows, header: header)

        assert {:ok, parsed} = Refract.CSV.stream({:string, csv})
        assert Enum.to_list(parsed) == rows
      end
    end
  end

  describe "write/3" do
    @describetag :tmp_dir

    test "writes encoded csv to a file", %{tmp_dir: dir} do
      path = Path.join(dir, "out.csv")

      assert :ok = Refract.CSV.write([%{"id" => "1"}], path, header: ["id"])
      assert File.read!(path) == "id\n1\n"
    end
  end
end
