defmodule Refract.Test.ReaderCase do
  @moduledoc """
  check/verify a custom reader will work with Refract.
  `load: false` for a reader whose sources have no byte size (a database query): leaves out the
  `load` test.

      use Refract.Test.ReaderCase,
        reader: MyReader,
        build: fn rows, dir -> MyReader.Fixture.write!(rows, dir) end
  """

  defmacro __using__(opts) do
    opts = Keyword.validate!(opts, [:reader, :build, load: true])
    reader = Keyword.fetch!(opts, :reader)
    build = Keyword.fetch!(opts, :build)
    load = Keyword.fetch!(opts, :load)

    validate_load(load)

    quote do
      use ExUnit.Case, async: true

      @moduletag :tmp_dir
      @moduletag timeout: 10_000

      @reader unquote(reader)

      defp build(rows, dir), do: unquote(build).(rows, dir)

      describe "reader conformance" do
        test "open gives each line as a list of cells", %{tmp_dir: dir} do
          rows = [["id", "name"], ["1", "alice"], ["2", "bob"]]

          assert {:ok, raw} = @reader.open(build(rows, dir), [])
          assert Enum.to_list(raw) == rows
        end

        test "stream gives row maps under the header", %{tmp_dir: dir} do
          source = build([["id", "name"], ["1", "alice"], ["2", "bob"]], dir)

          assert {:ok, rows} = @reader.stream(source)

          assert Enum.to_list(rows) == [
                   %{"id" => "1", "name" => "alice"},
                   %{"id" => "2", "name" => "bob"}
                 ]
        end

        test "stream normalises the header", %{tmp_dir: dir} do
          source = build([[" id ", ""], ["1", "x"]], dir)

          assert {:ok, rows} = @reader.stream(source)
          assert Enum.to_list(rows) == [%{"id" => "1", "col_1" => "x"}]
        end

        test "an empty source gives no rows", %{tmp_dir: dir} do
          assert {:ok, rows} = @reader.stream(build([], dir))
          assert Enum.to_list(rows) == []
        end

        test "a missing source is an error straight away", %{tmp_dir: dir} do
          assert {:error, _reason} = @reader.stream(Path.join(dir, "missing"))
        end

        test "locate finds the header below other lines", %{tmp_dir: dir} do
          source = build([["report", ""], ["", ""], ["id", "name"], ["1", "alice"]], dir)
          spec = Refract.Table.spec(header: [columns: %{"id" => ["id"], "name" => ["name"]}])

          assert {:ok, table} = @reader.locate(source, spec)
          assert table.header_row == 3
          assert Enum.to_list(table.rows) == [%{"id" => "1", "name" => "alice"}]
        end

        if unquote(load) do
          test "load builds a grid of the cells", %{tmp_dir: dir} do
            source = build([["id", "name"], ["1", "alice"]], dir)

            assert {:ok, grid} = @reader.load(source)
            assert Refract.Grid.cell(grid, "B2") == "alice"
          end
        end
      end
    end
  end

  defp validate_load(load) when is_boolean(load), do: :ok

  defp validate_load(load) do
    raise ArgumentError, "load must be true or false, got: #{inspect(load)}"
  end
end
