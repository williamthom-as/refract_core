defmodule Refract.ReaderTest do
  use ExUnit.Case, async: true

  defmodule StubReader do
    use Refract.Reader

    @impl Refract.Reader
    def open({:stream, rows}, _opts), do: {:ok, rows}

    def open(:missing, _opts), do: {:error, :enoent}
  end

  describe "stream/3" do
    test "first raw row becomes the header, the rest become row maps" do
      raw = [["id", "name"], ["1", "alice"], ["2", "bob"]]

      assert {:ok, rows} = Refract.Reader.stream(StubReader, {:stream, raw}, [])

      assert Enum.to_list(rows) == [
               %{"id" => "1", "name" => "alice"},
               %{"id" => "2", "name" => "bob"}
             ]
    end

    test "open error is returned as is, no stream" do
      assert {:error, :enoent} = Refract.Reader.stream(StubReader, :missing, [])
    end

    test "is lazy, nothing is read until enumerated" do
      test_pid = self()

      raw =
        Stream.map([["id"], ["1"], ["2"]], fn row ->
          send(test_pid, {:read, row})
          row
        end)

      assert {:ok, rows} = Refract.Reader.stream(StubReader, {:stream, raw}, [])

      refute_received {:read, _}

      assert Enum.take(rows, 1) == [%{"id" => "1"}]
    end
  end

  describe "stream/3 skip:" do
    test "drops n raw rows, the next row is the header" do
      raw = [["", ""], ["report", ""], ["id", "name"], ["1", "alice"]]

      assert {:ok, rows} = Refract.Reader.stream(StubReader, {:stream, raw}, skip: 2)
      assert Enum.to_list(rows) == [%{"id" => "1", "name" => "alice"}]
    end

    test "skip: 0 is the same as no skip" do
      raw = [["id"], ["1"]]

      assert {:ok, rows} = Refract.Reader.stream(StubReader, {:stream, raw}, skip: 0)
      assert Enum.to_list(rows) == [%{"id" => "1"}]
    end

    test "skipping past the end gives an empty stream" do
      raw = [["id"], ["1"]]

      assert {:ok, rows} = Refract.Reader.stream(StubReader, {:stream, raw}, skip: 5)
      assert Enum.to_list(rows) == []
    end

    test "stays lazy" do
      test_pid = self()

      raw =
        Stream.map([["junk"], ["id"], ["1"]], fn row ->
          send(test_pid, {:read, row})
          row
        end)

      assert {:ok, _rows} = Refract.Reader.stream(StubReader, {:stream, raw}, skip: 1)
      refute_received {:read, _}
    end
  end

  describe "use Refract.Reader" do
    test "injects stream/2 delegating to Reader.stream/3" do
      raw = [["id"], ["1"]]

      assert {:ok, rows} = StubReader.stream({:stream, raw})
      assert Enum.to_list(rows) == [%{"id" => "1"}]
    end
  end
end
