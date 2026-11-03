defmodule Refract.WriterTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000
  @moduletag :tmp_dir

  defmodule StubWriter do
    use Refract.Writer

    @impl Refract.Writer
    def encode_options, do: []

    @impl Refract.Writer
    def encode(rows, _opts), do: Stream.map(rows, fn row -> [row["id"], "\n"] end)

    @impl Refract.Writer
    def extension, do: "txt"
  end

  describe "use Refract.Writer" do
    test "injects write/3 that writes encode/2 output to a file", %{tmp_dir: dir} do
      path = Path.join(dir, "out.txt")

      assert :ok = StubWriter.write([%{"id" => "1"}, %{"id" => "2"}], path)
      assert File.read!(path) == "1\n2\n"
    end

    test "write/3 passes opts through to encode/2", %{tmp_dir: dir} do
      path = Path.join(dir, "out.txt")

      assert :ok = StubWriter.write([%{"id" => "1"}], path, header: ["id"])
      assert File.read!(path) == "1\n"
    end

    test "unwritable path is an error, not a crash", %{tmp_dir: dir} do
      path = Path.join([dir, "missing_dir", "out.txt"])

      assert {:error, :enoent} = StubWriter.write([%{"id" => "1"}], path)
    end
  end

  describe "cells/2" do
    alias Refract.Writer

    test "without a header, the first row's sorted keys then each row's values in that order" do
      rows = [%{"sku" => "A-1", "qty" => "2"}, %{"qty" => "5", "sku" => "B-2"}]

      assert rows |> Writer.cells(nil) |> Enum.to_list() == [
               ["qty", "sku"],
               ["2", "A-1"],
               ["5", "B-2"]
             ]
    end

    test "a header picks and orders the columns" do
      rows = [%{"sku" => "A-1", "qty" => "2", "note" => "x"}]

      assert rows |> Writer.cells(["sku", "qty"]) |> Enum.to_list() == [
               ["sku", "qty"],
               ["A-1", "2"]
             ]
    end

    test "values keep their types" do
      rows = [%{"total" => Decimal.new("1.50"), "on" => ~D[2026-10-05]}]

      assert [["on", "total"], [~D[2026-10-05], total]] =
               rows |> Writer.cells(nil) |> Enum.to_list()

      assert Decimal.eq?(total, "1.50")
    end

    test "a row missing a header column raises" do
      assert_raise KeyError, fn ->
        [%{"sku" => "A-1"}] |> Writer.cells(["sku", "qty"]) |> Enum.to_list()
      end

      assert_raise KeyError, fn ->
        [%{"sku" => "A-1", "qty" => "2"}, %{"sku" => "B-2"}]
        |> Writer.cells(nil)
        |> Enum.to_list()
      end
    end

    test "no rows: nothing without a header, the header alone with one" do
      assert [] |> Writer.cells(nil) |> Enum.to_list() == []
      assert [] |> Writer.cells(["sku"]) |> Enum.to_list() == [["sku"]]
    end

    test "lazy" do
      rows = Stream.repeatedly(fn -> %{"id" => "1"} end)

      assert rows |> Writer.cells(nil) |> Enum.take(3) == [["id"], ["1"], ["1"]]
    end
  end
end
