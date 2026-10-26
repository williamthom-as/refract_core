defmodule Refract.CSVEncodingTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag timeout: 10_000

  alias Refract.Classify
  alias Refract.CSV
  alias Refract.Shape
  alias Refract.Table

  @bom <<0xEF, 0xBB, 0xBF>>

  defp windows_1252,
    do:
      <<"name,city,note\nRen", 0xE9, "e,Montr", 0xE9, "al,", 0x80, "5 ", 0x93, "ok", 0x94, " ",
        0x96, " done\n">>

  defp rows!(source, opts \\ []) do
    {:ok, rows} = CSV.stream(source, opts)

    Enum.to_list(rows)
  end

  describe "reading, encoding: :auto by default" do
    test "a windows-1252 string reads as utf-8 text" do
      assert rows!({:string, windows_1252()}) == [
               %{"name" => "Renée", "city" => "Montréal", "note" => "€5 “ok” – done"}
             ]
    end

    test "a windows-1252 file reads as utf-8 text", %{tmp_dir: dir} do
      path = Path.join(dir, "people.csv")
      File.write!(path, windows_1252())

      assert [%{"name" => "Renée", "city" => "Montréal"}] = rows!(path)
    end

    test "a utf-8 file is unchanged" do
      assert rows!({:string, "name,city\nRenée,Montréal €\n"}) == [
               %{"name" => "Renée", "city" => "Montréal €"}
             ]
    end

    test "each line is decided on its own, so mixed files read" do
      mixed = <<"name\nRenée\nRen", 0xE9, "e\n">>

      assert rows!({:string, mixed}) == [%{"name" => "Renée"}, %{"name" => "Renée"}]
    end

    test "a windows-1252 line far past the start still reads" do
      filler = String.duplicate("plain\n", 15_000)
      source = {:string, "name\n" <> filler <> <<"Ren", 0xE9, "e\n">>}

      assert %{"name" => "Renée"} = source |> rows!() |> List.last()
    end

    test "a utf-16 file or string is a clear error, not garbage", %{tmp_dir: dir} do
      path = Path.join(dir, "unicode.txt")
      File.write!(path, <<0xFF, 0xFE, "n", 0, "\n", 0>>)

      assert {:error, {:unsupported_encoding, :utf16}} = CSV.stream(path)

      for bom <- [<<0xFF, 0xFE>>, <<0xFE, 0xFF>>] do
        assert {:error, {:unsupported_encoding, :utf16}} =
                 CSV.stream({:string, bom <> "n\x00a\x00m\x00e\x00\n\x00"})
      end
    end
  end

  describe "reading, a given encoding" do
    test ":utf8 keeps the bytes as they are" do
      assert [%{"name" => <<"Ren", 0xE9, "e">>}] =
               rows!({:string, <<"name\nRen", 0xE9, "e\n">>}, encoding: :utf8)
    end

    test ":latin1 and :windows_1252 differ only in 0x80 to 0x9F" do
      source = {:string, <<"name\n", 0x80, 0xE9, "\n">>}

      assert rows!(source, encoding: :windows_1252) == [%{"name" => "€é"}]
      assert rows!(source, encoding: :latin1) == [%{"name" => <<0xC2, 0x80, 0xC3, 0xA9>>}]
    end

    test ":windows_1252 decodes every line, even one that is valid utf-8" do
      source = {:string, <<"name\n", 0xC3, 0xA9, "\n">>}

      assert rows!(source, encoding: :windows_1252) == [%{"name" => "Ã©"}]
    end

    test "an unknown encoding raises" do
      assert_raise ArgumentError, fn -> CSV.stream({:string, "a\n1\n"}, encoding: :ebcdic) end
    end
  end

  describe "every reader entry point" do
    defp person do
      Shape.new(
        name: "person",
        spec: Table.spec(header: [columns: %{"first_name" => ["prénom"], "city" => ["ville"]}])
      )
    end

    defp french, do: <<"Pr", 0xE9, "nom,Ville\nRen", 0xE9, "e,Montr", 0xE9, "al\n">>

    test "classify matches an accented header in a windows-1252 file" do
      assert {:ok, %Classify.Result{verdict: :match}} =
               CSV.classify({:string, french()}, [person()])
    end

    test "locate reads it under the shape's columns, an encoding passes through" do
      assert {:ok, table} = CSV.locate({:string, french()}, person().spec)
      assert Enum.to_list(table.rows) == [%{"first_name" => "Renée", "city" => "Montréal"}]

      assert {:ok, _table} =
               CSV.locate({:string, french()}, person().spec, encoding: :windows_1252)
    end
  end

  describe "facts" do
    test "a utf-8 file" do
      assert {:ok, %{encoding: :utf8, encoding_source: :detected}} =
               CSV.facts({:string, "name\nRenée\n"})
    end

    test "a windows-1252 file" do
      assert {:ok, %{encoding: :windows_1252, encoding_source: :detected}} =
               CSV.facts({:string, windows_1252()})
    end

    test "utf-8 and windows-1252 lines together are mixed" do
      assert {:ok, %{encoding: :mixed}} =
               CSV.facts({:string, <<"name\nRenée\nRen", 0xE9, "e\n">>})
    end

    test "a given encoding is reported as given" do
      assert {:ok, %{encoding: :latin1, encoding_source: :given}} =
               CSV.facts({:string, "name\nRenee\n"}, encoding: :latin1)
    end

    test "a sample cut inside a character is still utf-8" do
      content = "name\n" <> String.duplicate("x", 65_535 - 5) <> "é\n"

      assert {:ok, %{encoding: :utf8}} = CSV.facts({:string, content})
    end

    test "a stream sample past 64 KB cut inside a character is still utf-8" do
      content = "name\n" <> String.duplicate("é\n", 40_000)
      chunks = for <<chunk::binary-size(1_000) <- content>>, do: chunk

      assert {:ok, %{encoding: :utf8}} = CSV.facts({:stream, chunks})
    end

    test "a utf-16 bom" do
      assert {:ok, %{encoding: :utf16}} = CSV.facts({:string, <<0xFF, 0xFE, "n", 0>>})
    end
  end

  describe "writing bom:" do
    test "bom: true starts the file with a utf-8 bom, by default there is none", %{
      tmp_dir: dir
    } do
      with_bom = Path.join(dir, "with.csv")
      without = Path.join(dir, "without.csv")

      :ok = CSV.write([%{"city" => "Montréal"}], with_bom, bom: true)
      :ok = CSV.write([%{"city" => "Montréal"}], without)

      assert File.read!(with_bom) == @bom <> "city\nMontréal\n"
      assert File.read!(without) == "city\nMontréal\n"
    end

    test "a file written with a bom reads back to the same rows", %{tmp_dir: dir} do
      path = Path.join(dir, "round.csv")
      rows = [%{"name" => "Renée", "city" => "Montréal"}]

      :ok = CSV.write(rows, path, bom: true)

      assert rows!(path) == rows
    end

    test "write_chunks passes bom: through to every part", %{tmp_dir: dir} do
      rows = for n <- 1..3, do: %{"n" => Integer.to_string(n)}

      assert {:ok, paths} =
               CSV.write_chunks(rows, dir, prefix: "part", rows_per_file: 2, bom: true)

      assert length(paths) == 2
      assert Enum.all?(paths, &String.starts_with?(File.read!(&1), @bom <> "n\n"))
    end
  end
end
