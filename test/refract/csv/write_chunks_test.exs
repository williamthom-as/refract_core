defmodule Refract.CSV.WriteChunksTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag timeout: 5_000

  alias Refract.CSV

  defp rows(n), do: for(i <- 1..n, do: %{"id" => "#{i}", "name" => "n#{i}"})

  defp opts(extra \\ []), do: Keyword.merge([prefix: "part", rows_per_file: 2], extra)

  test "splits rows into numbered files, each with the header", %{tmp_dir: dir} do
    assert {:ok, paths} = CSV.write_chunks(rows(5), dir, opts())

    assert paths == Enum.map(1..3, &Path.join(dir, "part_#{&1}.csv"))
    assert File.read!(Path.join(dir, "part_1.csv")) == "id,name\n1,n1\n2,n2\n"
    assert File.read!(Path.join(dir, "part_2.csv")) == "id,name\n3,n3\n4,n4\n"
    assert File.read!(Path.join(dir, "part_3.csv")) == "id,name\n5,n5\n"
  end

  test "an exact multiple leaves no empty last file", %{tmp_dir: dir} do
    assert {:ok, paths} = CSV.write_chunks(rows(4), dir, opts())

    assert length(paths) == 2
    assert dir |> File.ls!() |> Enum.sort() == ["part_1.csv", "part_2.csv"]
  end

  test "header sets the columns and order in every file", %{tmp_dir: dir} do
    assert {:ok, _paths} = CSV.write_chunks(rows(3), dir, opts(header: ["name", "id"]))

    assert File.read!(Path.join(dir, "part_1.csv")) == "name,id\nn1,1\nn2,2\n"
    assert File.read!(Path.join(dir, "part_2.csv")) == "name,id\nn3,3\n"
  end

  test "no rows writes no files", %{tmp_dir: dir} do
    assert CSV.write_chunks([], dir, opts()) == {:ok, []}
    assert File.ls!(dir) == []
  end

  test "a missing directory is an error and leaves nothing behind", %{tmp_dir: dir} do
    missing = Path.join(dir, "nope")

    assert {:error, :enoent} = CSV.write_chunks(rows(3), missing, opts())
    assert File.ls!(dir) == []
  end

  test "reads the source once", %{tmp_dir: dir} do
    test_pid = self()

    source =
      Stream.resource(
        fn ->
          send(test_pid, :opened)
          rows(5)
        end,
        fn
          [] -> {:halt, []}
          [row | rest] -> {[row], rest}
        end,
        fn _ -> :ok end
      )

    assert {:ok, [_, _, _]} = CSV.write_chunks(source, dir, opts())
    assert_received :opened
    refute_received :opened
  end

  test "missing prefix or rows_per_file raises", %{tmp_dir: dir} do
    assert_raise KeyError, fn -> CSV.write_chunks(rows(1), dir, rows_per_file: 2) end
    assert_raise KeyError, fn -> CSV.write_chunks(rows(1), dir, prefix: "part") end
  end

  test "rows_per_file must be a positive integer", %{tmp_dir: dir} do
    for bad <- [0, -1, 1.5, "2"] do
      assert_raise ArgumentError, fn ->
        CSV.write_chunks(rows(1), dir, opts(rows_per_file: bad))
      end
    end
  end

  test "unknown option raises", %{tmp_dir: dir} do
    assert_raise ArgumentError, fn -> CSV.write_chunks(rows(1), dir, opts(rows: 2)) end
  end
end
