defmodule Refract.ClassifyTest.Invoice do
  use Refract.Shape

  @impl Refract.Shape
  def shape, do: Refract.Shape.load!(Path.expand("../fixtures/inbox/shapes/invoice.yml", __DIR__))
end

defmodule Refract.ClassifyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  @moduletag timeout: 10_000

  alias Refract.Classify
  alias Refract.Classify.Candidate
  alias Refract.Classify.Result
  alias Refract.ClassifyTest.Invoice
  alias Refract.CSV
  alias Refract.Shape
  alias Refract.Table.Report.Line
  alias Refract.Table.Spec.Header

  @inbox Path.expand("../fixtures/inbox", __DIR__)

  defp path(name), do: Path.join(@inbox, name)

  defp shape(name), do: Shape.load!(Path.join([@inbox, "shapes", name <> ".yml"]))

  defp classify(file, shape_names, opts \\ []) do
    assert {:ok, %Result{} = result} =
             CSV.classify(path(file), Enum.map(shape_names, &shape/1), opts)

    result
  end

  defp candidate(result, name), do: Enum.find(result.candidates, &(&1.shape.name == name))

  describe "verdicts" do
    test "an exact file matches its shape" do
      result = classify("invoice.csv", ["invoice", "aws_bill"])

      assert %Result{verdict: :match, reason: nil, shape: %Shape{name: "invoice"}} = result
    end

    test "renamed columns match through aliases" do
      assert %Result{verdict: :match, shape: %Shape{name: "invoice"}} =
               classify("invoice_renamed.csv", ["invoice", "aws_bill"])
    end

    test "each shape matches its own file" do
      assert %Result{verdict: :match, shape: %Shape{name: "aws_bill"}} =
               classify("aws_bill.csv", ["invoice", "aws_bill"])
    end

    test "a header over invalid rows is obvious" do
      result = classify("bad_rows.csv", ["invoice", "aws_bill"])

      assert %Result{verdict: :unknown, reason: :rows_failed, shape: %Shape{name: "invoice"}} =
               result

      invoice = candidate(result, "invoice")

      assert %Candidate{status: :rows_failed, score: 0.0} = invoice
      assert invoice.header.passed
      assert Enum.map(invoice.rows, & &1.passed) == [false, false, false]
    end

    test "a file sharing some columns names the closest shape and what it lacks" do
      result = classify("stock_list.csv", ["invoice", "aws_bill"])

      assert %Result{verdict: :unknown, reason: :no_header, shape: %Shape{name: "invoice"}} =
               result

      invoice = candidate(result, "invoice")

      assert %Candidate{status: :no_header, score: 0.5, rows: []} = invoice
      refute invoice.header.passed
      assert Header.positions(invoice.header) == %{"sku" => 0, "item" => 1}
      assert Header.required_missing(invoice.header) == ["total"]
    end

    test "a file like no shape has no closest shape" do
      assert %Result{verdict: :unknown, reason: :no_header, shape: nil} =
               classify("unknown.csv", ["invoice", "aws_bill"])
    end

    test "an empty file has no closest shape and no header" do
      result = classify("empty.csv", ["invoice", "aws_bill"])

      assert %Result{verdict: :unknown, reason: :no_header, shape: nil} = result

      for candidate <- result.candidates do
        assert %Candidate{status: :no_header, score: 0.0, header: nil, rows: []} = candidate
      end
    end

    test "two near equal shapes are ambiguous" do
      result = classify("invoice.csv", ["invoice", "invoice_loose"])

      assert %Result{verdict: :ambiguous, reason: :within_margin, shape: nil} = result
      assert Enum.map(result.candidates, & &1.status) == [:matched, :matched]
    end

    test "file facts are not filled in yet" do
      assert %Result{file: nil} = classify("invoice.csv", ["invoice"])
    end
  end

  describe "candidates" do
    test "every shape is a candidate, matched ones first" do
      result = classify("invoice.csv", ["aws_bill", "invoice"])

      assert Enum.map(result.candidates, &{&1.shape.name, &1.status}) == [
               {"invoice", :matched},
               {"aws_bill", :no_header}
             ]
    end

    test "the header is the line it was found on" do
      result = classify("messy_invoice.csv", ["invoice"])

      assert %Line{check: :header, row: 10, passed: true} = candidate(result, "invoice").header
    end

    test "rows are checked from the header down to the stop" do
      invoice = "messy_invoice.csv" |> classify(["invoice"]) |> candidate("invoice")

      assert Enum.map(invoice.rows, &{&1.row, &1.check, &1.passed}) == [
               {11, :row, true},
               {12, :row, true},
               {13, :row, false},
               {14, :row, true}
             ]
    end

    test "score is header share times row pass rate" do
      assert %Candidate{status: :matched, score: 0.75} =
               "messy_invoice.csv" |> classify(["invoice"]) |> candidate("invoice")

      assert %Candidate{status: :matched, score: 0.75} =
               "invoice_short.csv" |> classify(["invoice"]) |> candidate("invoice")
    end

    test "a header with no rows under it scores on the header alone" do
      result = classify("header_only.csv", ["invoice"])

      assert %Result{verdict: :match} = result
      assert %Candidate{status: :matched, score: 1.0, rows: []} = candidate(result, "invoice")
    end

    test "a shape with no row rules scores on the header alone" do
      assert %Candidate{status: :matched, score: 1.0} =
               "invoice.csv" |> classify(["invoice_loose"]) |> candidate("invoice_loose")
    end
  end

  describe "options" do
    test "min_score: 0.0 accepts a header over invalid rows" do
      assert %Result{verdict: :match, shape: %Shape{name: "invoice"}} =
               classify("bad_rows.csv", ["invoice"], min_score: 0.0)
    end

    test "margin: 0.0 takes the first of two equal candidates" do
      assert %Result{verdict: :match, shape: %Shape{name: "invoice"}} =
               classify("invoice.csv", ["invoice", "invoice_loose"], margin: 0.0)
    end

    test "row cells are left out by default" do
      invoice = "invoice.csv" |> classify(["invoice"]) |> candidate("invoice")

      for row <- invoice.rows, {_column, column} <- row.columns do
        assert column.cell == nil
      end
    end

    test "values: true keeps row cells" do
      invoice = "invoice.csv" |> classify(["invoice"], values: true) |> candidate("invoice")

      assert hd(invoice.rows).columns["sku"].cell == "78632478"
    end

    test "within: limits the sample" do
      assert %Result{verdict: :unknown, reason: :no_header} =
               classify("messy_invoice.csv", ["invoice"], within: 9)

      result = classify("messy_invoice.csv", ["invoice"], within: 10)

      assert %Result{verdict: :match} = result
      assert %Candidate{rows: []} = candidate(result, "invoice")
    end

    test "reader options pass through" do
      assert %Result{verdict: :match, shape: %Shape{name: "invoice"}} =
               classify("invoice_semicolon.csv", ["invoice"], separator: ";")
    end

    test "shapes can be structs or shape modules" do
      assert {:ok, %Result{verdict: :match, shape: %Shape{name: "invoice"}}} =
               CSV.classify(path("invoice.csv"), [Invoice, shape("aws_bill")])
    end

    test "bad options raise" do
      for opts <- [
            [min_score: 2],
            [min_score: -0.1],
            [margin: 1.5],
            [margin: "0.1"],
            [within: -1],
            [values: "yes"]
          ] do
        assert_raise ArgumentError, fn ->
          CSV.classify(path("invoice.csv"), [shape("invoice")], opts)
        end
      end
    end

    test "no shapes raises" do
      assert_raise ArgumentError, ~r/shape/, fn -> CSV.classify(path("invoice.csv"), []) end
    end
  end

  describe "sources" do
    test "a missing file is an error" do
      assert {:error, :enoent} = CSV.classify(path("missing.csv"), [shape("invoice")])
    end

    property "never reads past within: lines" do
      check all(within <- integer(1..10)) do
        lines =
          Stream.concat(
            List.duplicate("a,b\n", within),
            Stream.map(["boom\n"], fn _ -> raise "read past within" end)
          )

        assert {:ok, %Result{}} =
                 CSV.classify({:stream, lines}, [shape("invoice")], within: within)
      end
    end
  end

  describe "lines/3" do
    @lines [["SKU", "Item", "Kg", "Line Total"], ["78632478", "apple", "2", "3"]]

    test "classifies lines without a reader" do
      assert %Result{verdict: :match, shape: %Shape{name: "invoice"}} =
               Classify.lines(@lines, [shape("invoice"), shape("aws_bill")])
    end

    test "takes the same options" do
      assert %Result{verdict: :unknown, reason: :no_header} =
               Classify.lines(@lines, [shape("invoice")], within: 0)

      assert_raise ArgumentError, fn -> Classify.lines(@lines, [shape("invoice")], margin: 2) end
      assert_raise ArgumentError, fn -> Classify.lines(@lines, []) end
    end
  end
end
