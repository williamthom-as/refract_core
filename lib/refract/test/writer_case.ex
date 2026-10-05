defmodule Refract.Test.WriterCase do
  @moduledoc """
  check/verify a custom writer will work with Refract.

      use Refract.Test.WriterCase,
        writer: MyWriter,
        read: fn path -> MyWriter.Fixture.read!(path) end
  """

  defmacro __using__(opts) do
    writer = Keyword.fetch!(opts, :writer)
    read = Keyword.fetch!(opts, :read)

    quote do
      use ExUnit.Case, async: true

      @moduletag :tmp_dir
      @moduletag timeout: 10_000

      @writer unquote(writer)

      defp read(path), do: unquote(read).(path)

      defp path(dir, name), do: Path.join(dir, "#{name}.#{@writer.extension()}")

      describe "writer conformance" do
        test "write gives the header then the rows", %{tmp_dir: dir} do
          path = path(dir, "out")
          rows = [%{"id" => "1", "name" => "alice"}, %{"id" => "2", "name" => "bob"}]

          assert :ok = @writer.write(rows, path, header: ["id", "name"])
          assert read(path) == [["id", "name"], ["1", "alice"], ["2", "bob"]]
        end

        test "header sets the columns and their order", %{tmp_dir: dir} do
          path = path(dir, "out")

          assert :ok =
                   @writer.write([%{"id" => "1", "name" => "alice"}], path,
                     header: ["name", "id"]
                   )

          assert read(path) == [["name", "id"], ["alice", "1"]]
        end

        test "without a header the columns are the first rows keys sorted", %{tmp_dir: dir} do
          path = path(dir, "out")

          assert :ok = @writer.write([%{"name" => "alice", "id" => "1"}], path)
          assert read(path) == [["id", "name"], ["1", "alice"]]
        end

        test "write_chunks numbers files with the writers extension", %{tmp_dir: dir} do
          rows = for i <- 1..3, do: %{"id" => "#{i}"}

          assert {:ok, paths} = @writer.write_chunks(rows, dir, prefix: "part", rows_per_file: 2)
          assert paths == [path(dir, "part_1"), path(dir, "part_2")]
          assert read(path(dir, "part_2")) == [["id"], ["3"]]
        end

        test "a stream that fails part way leaves nothing behind", %{tmp_dir: dir} do
          rows =
            Stream.map([1, 2], fn
              1 -> %{"id" => "1"}
              2 -> raise "source failed"
            end)

          assert_raise RuntimeError, fn -> @writer.write(rows, path(dir, "out")) end
          assert File.ls!(dir) == []
        end

        test "an unwritable path is an error", %{tmp_dir: dir} do
          assert {:error, _reason} = @writer.write([%{"id" => "1"}], path(dir, "missing/out"))
        end

        test "extension is a name without a dot" do
          assert is_binary(@writer.extension())
          assert @writer.extension() =~ ~r/^[a-z0-9]+$/
        end
      end
    end
  end
end
