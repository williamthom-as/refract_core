defmodule Refract.LoadMaxRowsTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag timeout: 10_000

  alias Refract.CSV
  alias Refract.Grid
  alias Refract.Shape
  alias Refract.Table
  alias Refract.TestReaders.Memory

  @lines [["sku", "qty"], ["A-100", "2"], ["B-200", "3"]]

  defp memory, do: %Memory{lines: @lines}

  defp stream, do: {:stream, ["sku,qty\n", "A-100,2\n", "B-200,3\n"]}

  defp csv_file!(dir) do
    path = Path.join(dir, "lines.csv")
    File.write!(path, "sku,qty\nA-100,2\nB-200,3\n")
    path
  end

  defp reads_received(count) do
    receive do
      :read -> reads_received(count + 1)
    after
      0 -> count
    end
  end

  defp totalled do
    Shape.new(
      name: "lines",
      spec: Table.spec(header: [columns: %{"sku" => ["sku"], "qty" => ["qty"]}]),
      validation: [document: [{:has_rows, fn %{rows: rows} -> rows != [] end}]]
    )
  end

  describe "load/2 max_rows:" do
    test "a file within the cap loads", %{tmp_dir: dir} do
      assert {:ok, %Grid{} = grid} = CSV.load(csv_file!(dir), max_rows: 3)
      assert Grid.cell(grid, "A3") == "B-200"
    end

    test "a file over the cap is an error naming the cap", %{tmp_dir: dir} do
      assert {:error, {:max_rows_exceeded, 2}} = CSV.load(csv_file!(dir), max_rows: 2)
    end

    test "a stream loads with a cap, and is refused without one" do
      assert {:ok, %Grid{}} = CSV.load(stream(), max_rows: 3)
      assert {:error, {:stream_not_allowed, _source}} = CSV.load(stream())
    end

    test "a source struct loads with a cap, and is unsupported without one" do
      assert {:ok, %Grid{} = grid} = Memory.load(memory(), max_rows: 3)
      assert Grid.cell(grid, "B2") == "2"
      assert {:error, {:unsupported_source, _source}} = Memory.load(memory())
    end

    test "a source struct over the cap is an error" do
      assert {:error, {:max_rows_exceeded, 1}} = Memory.load(memory(), max_rows: 1)
    end

    test "at most one line past the cap is read" do
      test_pid = self()
      lines = Stream.map(Stream.cycle([["x"]]), &tap(&1, fn _line -> send(test_pid, :read) end))

      assert {:error, {:max_rows_exceeded, 5}} = Memory.load(%Memory{lines: lines}, max_rows: 5)
      assert reads_received(0) == 6
    end

    test "on a file both caps apply", %{tmp_dir: dir} do
      path = csv_file!(dir)

      assert {:error, {:max_bytes_exceeded, 10}} = CSV.load(path, max_rows: 100, max_bytes: 10)
      assert {:error, {:max_rows_exceeded, 2}} = CSV.load(path, max_rows: 2, max_bytes: 1_000)
      assert {:ok, %Grid{}} = CSV.load(path, max_rows: 3, max_bytes: 1_000)
    end

    test "a missing file is still its error", %{tmp_dir: dir} do
      assert {:error, :enoent} = CSV.load(Path.join(dir, "missing.csv"), max_rows: 10)
    end

    test "max_rows is checked" do
      for max_rows <- [0, -1, "10", 1.5] do
        assert_raise ArgumentError, ~r/max_rows must be a positive integer/, fn ->
          Memory.load(memory(), max_rows: max_rows)
        end
      end
    end
  end

  describe "through validate and fields" do
    test "document rules validate a source struct with a cap" do
      assert {:ok, %Refract.Validate.Result{valid: true, rows: 2}} =
               Memory.validate(memory(), totalled(), max_rows: 10)
    end

    test "document rules on a source struct without a cap are unsupported" do
      assert {:error, {:unsupported_source, _source}} = Memory.validate(memory(), totalled())
    end

    test "document rules on a stream over the cap are an error" do
      assert {:error, {:max_rows_exceeded, 2}} =
               CSV.validate(stream(), totalled(), max_rows: 2)
    end

    test "fields read a stream with a cap" do
      shape =
        Shape.new(
          name: "lines",
          spec: Table.spec(header: [columns: %{"sku" => ["sku"], "qty" => ["qty"]}]),
          fields: %{"first_sku" => [at: "A2"]}
        )

      assert {:ok, %{"first_sku" => "A-100"}} = CSV.fields(stream(), shape, max_rows: 10)
    end
  end
end
