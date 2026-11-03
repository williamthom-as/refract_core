defmodule Refract.ReaderTest do
  use ExUnit.Case, async: true

  defmodule StubReader do
    use Refract.Reader

    @impl Refract.Reader
    def open_options, do: []

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

  describe "for_path/2" do
    test "csv and tsv go to the csv reader whatever their case" do
      assert Refract.Reader.for_path("bills.csv") == {:ok, {Refract.CSV, []}}
      assert Refract.Reader.for_path("BILLS.TSV") == {:ok, {Refract.CSV, []}}
    end

    test "a caller reader adds its extensions, with its options" do
      readers = [{Refract.TestReaders.Txt, separator: "|"}]

      assert Refract.Reader.for_path("bills.txt", readers) ==
               {:ok, {Refract.TestReaders.Txt, [separator: "|"]}}
    end

    test "anything else is unsupported" do
      assert Refract.Reader.for_path("notes.md") == {:error, {:unsupported, "md"}}
      assert Refract.Reader.for_path("README") == {:error, {:unsupported, ""}}
    end
  end

  describe "use Refract.Reader" do
    test "injects stream/2 delegating to Reader.stream/3" do
      raw = [["id"], ["1"]]

      assert {:ok, rows} = StubReader.stream({:stream, raw})
      assert Enum.to_list(rows) == [%{"id" => "1"}]
    end
  end

  describe "indexing" do
    alias Refract.Shape
    alias Refract.Table

    defmodule RecordsReader do
      use Refract.Reader

      @impl Refract.Reader
      def open_options, do: []

      @impl Refract.Reader
      def open({:stream, rows}, _opts), do: {:ok, rows}

      @impl Refract.Reader
      def indexing, do: :records
    end

    @records [["account", "amount"], ["A-1", "1.00"], ["A-2", "n/a"], ["A-3", "north"]]

    defp ledger do
      Shape.new(
        name: "ledger",
        spec: Table.spec(header: [columns: %{"account" => ["account"], "amount" => ["amount"]}]),
        validation: [columns: %{"amount" => [:number]}]
      )
    end

    test "a reader that makes its header up counts records from 1" do
      assert {:ok, %{issues: [%{line: 2}, %{line: 3}]}} =
               RecordsReader.validate({:stream, @records}, ledger())
    end

    test "a reader counting lines keeps file lines" do
      assert {:ok, %{issues: [%{line: 3}, %{line: 4}]}} =
               StubReader.validate({:stream, @records}, ledger())
    end

    test "profile lines follow the reader too" do
      rows = [["account", "amount"], ["A-1", "north"], ["A-2", "North"]]

      assert {:ok, %{columns: %{"amount" => %{clusters: [%{variants: variants}]}}}} =
               RecordsReader.profile({:stream, rows}, ledger())

      assert Enum.map(variants, & &1.lines) == [[1], [2]]
    end

    test "a reader without indexing counts lines" do
      assert Refract.Reader.indexing(StubReader) == :lines
      assert Refract.Reader.indexing(RecordsReader) == :records
    end

    test "indexing is :lines or :records" do
      assert_raise ArgumentError, ~r/indexing/, fn ->
        StubReader.validate({:stream, @records}, ledger(), indexing: :rows)
      end
    end
  end

  describe "options" do
    alias Refract.Classify.Score
    alias Refract.CSV
    alias Refract.Profile.Count
    alias Refract.Shape
    alias Refract.Table
    alias Refract.Table.Locate
    alias Refract.Validate

    @source {:string, "account,amount\nA-1,1.00\n"}

    defp shape do
      Shape.new(
        name: "ledger",
        spec: Table.spec(header: [columns: %{"account" => ["account"], "amount" => ["amount"]}])
      )
    end

    defp each_option(options, fun), do: Enum.each(options, &fun.([&1]))

    test "every option a module declares reaches it, none is taken for the file reader" do
      each_option(
        Locate.options(),
        &assert({:ok, _table} = CSV.locate(@source, shape().spec, &1))
      )

      each_option(Score.options(), &assert({:ok, _result} = CSV.classify(@source, [shape()], &1)))

      each_option(
        Locate.header_options(),
        &assert({:ok, _report} = CSV.suggest(@source, shape(), &1))
      )

      each_option(
        Locate.header_options() ++ Count.options(),
        &assert({:ok, _result} = CSV.profile(@source, shape(), &1))
      )

      each_option(
        Locate.header_options() ++ Validate.options(),
        &assert({:ok, _result} = CSV.validate(@source, shape(), &1))
      )
    end
  end

  describe "a source struct" do
    alias Refract.Classify.Facts
    alias Refract.Classify.Result
    alias Refract.Shape
    alias Refract.Table
    alias Refract.TestReaders.Memory

    @memory %Memory{lines: [["account", "amount"], ["A-1", "1.00"], ["A-2", "2.50"]]}

    defp ledger_shape do
      Shape.new(
        name: "ledger",
        spec: Table.spec(header: [columns: %{"account" => ["account"], "amount" => ["amount"]}])
      )
    end

    test "stream gives row maps" do
      assert {:ok, rows} = Memory.stream(@memory)

      assert Enum.to_list(rows) == [
               %{"account" => "A-1", "amount" => "1.00"},
               %{"account" => "A-2", "amount" => "2.50"}
             ]
    end

    test "classify has no path or name and an unknown size, the reader facts kept" do
      assert {:ok, %Result{verdict: :match, file: file} = result} =
               Memory.classify(@memory, [ledger_shape()])

      assert %Facts{path: nil, size: :unknown, format: %{lines: 3}} = file
      assert %Result{reader: {Memory, []}} = result
    end

    test "validate and profile read it" do
      assert {:ok, %Refract.Validate.Result{}} = Memory.validate(@memory, ledger_shape())
      assert {:ok, %Refract.Profile.Result{}} = Memory.profile(@memory, ledger_shape())
    end

    test "load is unsupported" do
      assert {:error, {:unsupported_source, @memory}} = Memory.load(@memory)
    end
  end
end
