defmodule Refract.Classify.FolderTest.CountedInvoice do
  use Refract.Shape

  @impl Refract.Shape
  def shape do
    send(:classify_folder_test, :resolved)

    Refract.Shape.load!(Path.expand("../../fixtures/inbox/shapes/invoice.yml", __DIR__))
  end
end

defmodule Refract.Classify.FolderTest.CrashingReader do
  use Refract.Reader

  @impl Refract.Reader
  def open(_source, _opts), do: raise("reader bug")
end

defmodule Refract.Classify.FolderTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag timeout: 10_000

  alias Refract.Classify
  alias Refract.Classify.FolderTest.CountedInvoice
  alias Refract.Classify.FolderTest.CrashingReader

  alias Refract.Classify.Result
  alias Refract.CSV
  alias Refract.Shape

  @inbox Path.expand("../../fixtures/inbox", __DIR__)

  defp shape(name), do: Shape.load!(Path.join([@inbox, "shapes", name <> ".yml"]))

  defp copy(dir, name, as \\ nil) do
    target = Path.join(dir, as || name)

    File.cp!(Path.join(@inbox, name), target)

    target
  end

  defp folder(dir, shape_names, opts \\ []) do
    assert {:ok, stream} = Classify.folder(dir, Enum.map(shape_names, &shape/1), opts)

    Enum.to_list(stream)
  end

  defp verdicts(results) do
    for {path, {:ok, %Result{verdict: verdict, shape: shape}}} <- results,
        do: {Path.basename(path), verdict, shape && shape.name}
  end

  describe "folder/3" do
    test "every file gets a result, in path order", %{tmp_dir: dir} do
      copy(dir, "invoice.csv")
      copy(dir, "aws_bill.csv")
      copy(dir, "unknown.csv")

      assert dir |> folder(["invoice", "aws_bill"]) |> verdicts() == [
               {"aws_bill.csv", :match, "aws_bill"},
               {"invoice.csv", :match, "invoice"},
               {"unknown.csv", :unknown, nil}
             ]
    end

    test "each result is the same as classifying the file alone", %{tmp_dir: dir} do
      path = copy(dir, "messy_invoice.csv")
      shapes = [shape("invoice"), shape("aws_bill")]

      assert {:ok, stream} = Classify.folder(dir, shapes)
      assert [{^path, result}] = Enum.to_list(stream)
      assert result == CSV.classify(path, shapes)
    end

    test "file names feed the file markers", %{tmp_dir: dir} do
      copy(dir, "acme_plain.csv", "acme_nz.csv")

      assert [{_path, {:ok, %Result{verdict: :match, reason: :markers, shape: shape}}}] =
               folder(dir, ["invoice_au", "invoice_nz"])

      assert shape.name == "invoice_nz"
    end

    test "an unsupported file is reported, not skipped", %{tmp_dir: dir} do
      notes = Path.join(dir, "notes.txt")
      File.write!(notes, "SKU,Item,Kg,Line Total\n")

      assert [{^notes, {:error, {:unsupported, "txt"}}}] = folder(dir, ["invoice"])
    end

    test "a file without an extension is unsupported", %{tmp_dir: dir} do
      readme = Path.join(dir, "README")
      File.write!(readme, "notes\n")

      assert [{^readme, {:error, {:unsupported, ""}}}] = folder(dir, ["invoice"])
    end

    test "extensions match whatever the case", %{tmp_dir: dir} do
      copy(dir, "invoice.csv", "INVOICE.CSV")

      assert dir |> folder(["invoice"]) |> verdicts() == [{"INVOICE.CSV", :match, "invoice"}]
    end

    test "tsv files read with a tab", %{tmp_dir: dir} do
      tsv = Path.join(dir, "invoice.tsv")
      File.write!(tsv, "SKU\tItem\tKg\tLine Total\n78632478\tapple\t2\t3\n")

      assert [{^tsv, {:ok, %Result{verdict: :match} = result}}] = folder(dir, ["invoice"])
      assert %{delimiter: "\t", delimiter_source: :given} = result.file.format
    end

    test "readers: adds a reader for another extension", %{tmp_dir: dir} do
      copy(dir, "invoice.csv", "invoice.txt")
      copy(dir, "invoice.csv")

      assert dir |> folder(["invoice"], readers: %{"txt" => CSV}) |> verdicts() == [
               {"invoice.csv", :match, "invoice"},
               {"invoice.txt", :match, "invoice"}
             ]
    end

    test "a reader can carry its own options", %{tmp_dir: dir} do
      copy(dir, "invoice_semicolon.csv")

      assert [{_path, {:ok, %Result{verdict: :match} = result}}] =
               folder(dir, ["invoice"], readers: %{"csv" => {CSV, separator: ";"}})

      assert %{delimiter: ";", delimiter_source: :given} = result.file.format
    end

    test "classify options apply to every file", %{tmp_dir: dir} do
      copy(dir, "bad_rows.csv")

      assert dir |> folder(["invoice"], min_score: 0.0) |> verdicts() == [
               {"bad_rows.csv", :match, "invoice"}
             ]
    end

    test "a file that cannot be read is an error, the rest carry on", %{tmp_dir: dir} do
      copy(dir, "invoice.csv")
      broken = Path.join(dir, "broken.csv")
      File.write!(broken, "SKU,Item\n\"unclosed,quote\n")
      File.chmod!(broken, 0o000)

      results = folder(dir, ["invoice"])

      assert [{^broken, {:error, _reason}}, {_invoice, {:ok, %Result{verdict: :match}}}] = results
    after
      File.chmod(Path.join(dir, "broken.csv"), 0o644)
    end

    test "a malformed file is a parse error, the rest carry on", %{tmp_dir: dir} do
      malformed = Path.join(dir, "a_malformed.csv")
      File.write!(malformed, "SKU,Item\n78632478,\"apple\n")
      copy(dir, "invoice.csv")

      assert [
               {^malformed, {:error, {:parse_error, _message}}},
               {_invoice, {:ok, %Result{verdict: :match}}}
             ] = folder(dir, ["invoice"])
    end

    test "a reader that raises is reported as crashed, the rest carry on", %{tmp_dir: dir} do
      crashing = Path.join(dir, "a_crash.boom")
      File.write!(crashing, "anything")
      copy(dir, "invoice.csv")

      assert [
               {^crashing, {:error, {:crashed, %RuntimeError{message: "reader bug"}}}},
               {_invoice, {:ok, %Result{verdict: :match}}}
             ] = folder(dir, ["invoice"], readers: %{"boom" => CrashingReader})
    end

    test "dot files are skipped", %{tmp_dir: dir} do
      copy(dir, "invoice.csv")
      copy(dir, "invoice.csv", ".hidden.csv")
      copy(dir, "invoice.csv", ".~lock.invoice.csv#")
      File.write!(Path.join(dir, ".DS_Store"), "junk")

      assert [{invoice, {:ok, %Result{verdict: :match}}}] = folder(dir, ["invoice"])
      assert Path.basename(invoice) == "invoice.csv"
    end

    test "office lock files and windows thumbnail and folder files are skipped", %{tmp_dir: dir} do
      copy(dir, "invoice.csv")
      copy(dir, "invoice.csv", "~$invoice.csv")
      File.write!(Path.join(dir, "Thumbs.db"), "junk")
      File.write!(Path.join(dir, "desktop.ini"), "junk")

      assert [{invoice, {:ok, %Result{verdict: :match}}}] = folder(dir, ["invoice"])
      assert Path.basename(invoice) == "invoice.csv"
    end

    test "subdirectories are not entered", %{tmp_dir: dir} do
      copy(dir, "invoice.csv")
      File.mkdir_p!(Path.join(dir, "nested"))
      File.cp!(Path.join(@inbox, "invoice.csv"), Path.join([dir, "nested", "invoice.csv"]))

      assert dir |> folder(["invoice"]) |> verdicts() == [{"invoice.csv", :match, "invoice"}]
    end

    test "an empty folder gives no results", %{tmp_dir: dir} do
      assert folder(dir, ["invoice"]) == []
    end

    test "shapes are resolved once for the whole folder", %{tmp_dir: dir} do
      Process.register(self(), :classify_folder_test)

      copy(dir, "invoice.csv")
      copy(dir, "invoice_renamed.csv")
      copy(dir, "invoice_short.csv")

      assert {:ok, stream} = Classify.folder(dir, [CountedInvoice])
      assert length(Enum.to_list(stream)) == 3

      assert_received :resolved
      refute_received :resolved
    end

    test "a missing folder is an error", %{tmp_dir: dir} do
      assert {:error, :enoent} = Classify.folder(Path.join(dir, "missing"), [shape("invoice")])
    end

    test "bad options raise", %{tmp_dir: dir} do
      for opts <- [
            [max_concurrency: 0],
            [readers: [csv: CSV]],
            [readers: %{"csv" => "CSV"}],
            [min_score: 2],
            [colour: :blue]
          ] do
        assert_raise ArgumentError, fn -> Classify.folder(dir, [shape("invoice")], opts) end
      end
    end

    test "no shapes raises", %{tmp_dir: dir} do
      assert_raise ArgumentError, ~r/shape/, fn -> Classify.folder(dir, []) end
    end
  end
end
