defmodule Refract.WriterTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000
  @moduletag :tmp_dir

  defmodule StubWriter do
    use Refract.Writer

    @impl Refract.Writer
    def encode(rows, _opts), do: Stream.map(rows, fn row -> [row["id"], "\n"] end)
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
end
