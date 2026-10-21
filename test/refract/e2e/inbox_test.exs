defmodule Refract.E2E.InboxTest do
  use ExUnit.Case, async: true

  @moduletag :e2e
  @moduletag :yaml
  @moduletag :tmp_dir
  @moduletag timeout: 10_000

  alias Refract.Classify
  alias Refract.Classify.Result
  alias Refract.CSV
  alias Refract.Errors.ParseError
  alias Refract.Privacy.Keyring
  alias Refract.Privacy.Pseudonym
  alias Refract.Rows
  alias Refract.Shape

  @fixtures Path.expand("../../fixtures/inbox", __DIR__)

  @keyring Keyring.new!(keys: %{1 => :binary.copy(<<1>>, 32)})

  @shape_names ["aws_bill", "invoice", "summary"]

  defp shapes do
    Enum.map(@shape_names, &Shape.load!(Path.join([@fixtures, "shapes", &1 <> ".yml"])))
  end

  defp run(inbox, out) do
    {:ok, results} = Classify.folder(inbox, shapes())

    results
    |> Task.async_stream(fn {path, result} -> {Path.basename(path), route(path, result, out)} end,
      ordered: false,
      timeout: :infinity
    )
    |> Map.new(fn {:ok, item} -> item end)
  end

  defp route(path, {:ok, %Result{verdict: :match} = result}, out), do: write(path, result, out)

  defp route(path, {:ok, %Result{verdict: verdict, reason: reason}}, out),
    do: set_aside(path, "_#{verdict}", reason, out)

  defp route(path, {:error, reason}, out), do: set_aside(path, "_failed", reason, out)

  defp write(path, %Result{shape: shape} = result, out) do
    %{header: header} = Enum.find(result.candidates, &(&1.shape == shape))
    dir = Path.join(out, shape.name)
    File.mkdir_p!(dir)

    with {:ok, table} <- CSV.locate(path, shape.spec, header_row: header.row),
         :ok <-
           table.rows
           |> private(shape)
           |> CSV.write(Path.join(dir, Path.basename(path)), header: columns(shape)) do
      {:written, shape.name}
    else
      {:error, reason} -> set_aside(path, "_failed", reason, out)
    end
  rescue
    error in ParseError -> set_aside(path, "_failed", {:parse_error, error.message}, out)
  end

  defp columns(%Shape{spec: spec}), do: spec.header.columns |> Map.keys() |> Enum.sort()

  defp private(rows, %Shape{name: "aws_bill"}),
    do: Rows.update(rows, "account", &Pseudonym.apply!(&1, :aws_account, @keyring))

  defp private(rows, _shape), do: rows

  defp set_aside(path, folder, reason, out) do
    dir = Path.join(out, folder)
    File.mkdir_p!(dir)

    File.cp!(path, Path.join(dir, Path.basename(path)))
    File.write!(Path.join(dir, Path.basename(path) <> ".reason"), inspect(reason))

    {:set_aside, folder, reason}
  end

  defp inbox(dir) do
    inbox = Path.join(dir, "inbox")
    File.mkdir_p!(inbox)

    for name <- File.ls!(@fixtures), File.regular?(Path.join(@fixtures, name)) do
      File.cp!(Path.join(@fixtures, name), Path.join(inbox, name))
    end

    rows = for n <- 1..150, do: "#{10_000_000 + n},apple,1,#{n}\n"

    File.write!(Path.join(inbox, "late_malformed.csv"), [
      "SKU,Item,Kg,Line Total\n",
      rows,
      "\"bad\n"
    ])

    inbox
  end

  defp shape_folders(out) do
    out |> File.ls!() |> Enum.reject(&String.starts_with?(&1, "_")) |> Enum.sort()
  end

  defp written(out, folder) do
    out |> Path.join(folder) |> File.ls!() |> Enum.sort()
  end

  defp rows(path) do
    {:ok, rows} = CSV.stream(path)

    Enum.to_list(rows)
  end

  describe "an inbox through classify, locate, privacy and write" do
    setup %{tmp_dir: dir} do
      out = Path.join(dir, "out")

      %{out: out, routes: run(inbox(dir), out)}
    end

    test "every file is written to its shape folder or set aside with its reason", %{
      routes: routes
    } do
      assert routes == %{
               "README.md" => {:set_aside, "_failed", {:unsupported, "md"}},
               "acme_au.csv" => {:written, "invoice"},
               "acme_nz.csv" => {:written, "invoice"},
               "acme_plain.csv" => {:written, "invoice"},
               "acme_q3.csv" => {:written, "invoice"},
               "aws_bill.csv" => {:written, "aws_bill"},
               "aws_bill_october.csv" => {:written, "aws_bill"},
               "bad_rows.csv" => {:set_aside, "_unknown", :rows_failed},
               "bad_table_then_good.csv" => {:written, "invoice"},
               "empty.csv" => {:set_aside, "_unknown", :no_header},
               "header_only.csv" => {:written, "invoice"},
               "invoice.csv" => {:written, "invoice"},
               "invoice_renamed.csv" => {:written, "invoice"},
               "invoice_semicolon.csv" => {:written, "invoice"},
               "invoice_short.csv" => {:written, "invoice"},
               "late_malformed.csv" =>
                 {:set_aside, "_failed",
                  {:parse_error, "expected escape character \" but reached the end of file"}},
               "messy_invoice.csv" => {:written, "invoice"},
               "quoted_header.csv" => {:written, "invoice"},
               "stock_list.csv" => {:set_aside, "_unknown", :no_header},
               "summary_then_invoice.csv" => {:set_aside, "_ambiguous", :within_margin},
               "unknown.csv" => {:set_aside, "_unknown", :no_header}
             }
    end

    test "every file of a shape has the shape columns as its header", %{out: out} do
      assert shape_folders(out) == ["aws_bill", "invoice"]

      for shape <- shapes(), shape.name in shape_folders(out), file <- written(out, shape.name) do
        header = out |> Path.join(shape.name) |> Path.join(file) |> File.stream!() |> Enum.at(0)

        assert String.trim_trailing(header) == Enum.join(columns(shape), ",")
      end
    end

    test "rows land under the shape columns, wherever the file had them", %{out: out} do
      assert rows(Path.join([out, "invoice", "messy_invoice.csv"])) == [
               %{"sku" => "78632478", "item" => "apple", "kg" => "2", "total" => "3"},
               %{"sku" => "12319082", "item" => "oarnge", "kg" => "2", "total" => "5"}
             ]

      assert rows(Path.join([out, "invoice", "bad_table_then_good.csv"])) != []
    end

    test "set aside files keep their content and say why", %{out: out} do
      assert File.read!(Path.join([out, "_ambiguous", "summary_then_invoice.csv"])) ==
               File.read!(Path.join(@fixtures, "summary_then_invoice.csv"))

      assert File.read!(Path.join([out, "_ambiguous", "summary_then_invoice.csv.reason"])) ==
               ":within_margin"
    end

    test "a parse error past the classify sample leaves nothing in the shape folder", %{out: out} do
      refute "late_malformed.csv" in written(out, "invoice")
      assert "late_malformed.csv" in written(out, "_failed")
    end

    test "each shape folder classifies back to its shape", %{out: out} do
      for folder <- shape_folders(out) do
        {:ok, results} = Classify.folder(Path.join(out, folder), shapes())

        for {path, result} <- results do
          assert {:ok, %Result{verdict: :match, shape: %Shape{name: ^folder}}} = result,
                 "#{folder}/#{Path.basename(path)}"
        end
      end
    end

    test "pseudonymised account ids still join across files", %{out: out} do
      september = rows(Path.join([out, "aws_bill", "aws_bill.csv"]))
      october = rows(Path.join([out, "aws_bill", "aws_bill_october.csv"]))

      original = rows(Path.join(@fixtures, "aws_bill.csv"))

      for {row, source} <- Enum.zip(september, original) do
        assert row["account"] =~ ~r/^\d{12}$/
        assert row["account"] != source["lineItem/UsageAccountId"]
      end

      [first_september | _] = september
      [first_october | _] = october

      assert first_september["account"] == first_october["account"]

      assert Pseudonym.reverse!(first_october["account"], :aws_account, @keyring) ==
               "123456789012"
    end
  end
end
