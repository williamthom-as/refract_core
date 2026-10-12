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
  alias Refract.Classify.Facts
  alias Refract.Classify.Marker
  alias Refract.Classify.Result
  alias Refract.ClassifyTest.Invoice
  alias Refract.CSV
  alias Refract.Shape
  alias Refract.Table
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

    test "header cells wrapped in literal quotes match" do
      assert %Result{verdict: :match, shape: %Shape{name: "invoice"}} =
               classify("quoted_header.csv", ["invoice", "aws_bill"])
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

      assert %Candidate{status: :rows_failed, score: +0.0} = invoice
      assert invoice.header.passed
      assert [%Line{row: 2, passed: false}] = invoice.rows
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
        assert %Candidate{status: :no_header, score: +0.0, header: nil, rows: []} = candidate
      end
    end

    test "a shape matching part of another shape's header gives way to it" do
      result = classify("invoice.csv", ["invoice_loose", "invoice"])

      assert %Result{verdict: :match, reason: :wider_header, shape: %Shape{name: "invoice"}} =
               result

      assert Enum.map(result.candidates, & &1.status) == [:matched, :matched]
    end

    test "a narrower shape with the higher score still gives way on the same header" do
      assert %Result{verdict: :match, reason: :wider_header, shape: %Shape{name: "invoice"}} =
               classify("invoice_short.csv", ["summary", "invoice"])
    end

    test "a wider header that wins clearly anyway needs no reason" do
      narrow =
        Shape.from_map!(%{
          "name" => "narrow",
          "header" => %{"columns" => %{"sku" => ["sku"], "total" => ["line total"]}},
          "row" => %{"match" => %{"total" => "integer"}}
        })

      assert {:ok, %Result{verdict: :match, reason: nil, shape: %Shape{name: "invoice"}}} =
               CSV.classify(path("invoice.csv"), [narrow, shape("invoice")])
    end

    test "a tie between overlapping shapes on the same header goes to more columns" do
      overlapping = fn name, columns ->
        Shape.from_map!(%{"name" => name, "header" => %{"columns" => columns}})
      end

      item = overlapping.("item", %{"sku" => ["sku"], "item" => ["item"]})
      kg = overlapping.("kg", %{"sku" => ["sku"], "kg" => ["kg"], "total" => ["line total"]})

      assert {:ok, %Result{verdict: :match, reason: :most_columns, shape: %Shape{name: "kg"}}} =
               CSV.classify(path("invoice.csv"), [item, kg])
    end

    test "a later version adding columns wins over the earlier version" do
      columns = %{"sku" => ["sku"], "item" => ["item"], "total" => ["line total"]}

      v1 = %{"name" => "invoice", "version" => 1, "header" => %{"columns" => columns}}

      v2 =
        put_in(v1, ["header", "columns"], Map.put(columns, "kg", ["kg"]))
        |> Map.put("version", 2)

      assert {:ok, %Result{verdict: :match, reason: :wider_header, shape: shape}} =
               CSV.classify(path("invoice.csv"), [Shape.from_map!(v1), Shape.from_map!(v2)])

      assert %Shape{name: "invoice", version: 2} = shape
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

    test "rows are checked down to the failing row that ends the table" do
      invoice = "messy_invoice.csv" |> classify(["invoice"]) |> candidate("invoice")

      assert Enum.map(invoice.rows, &{&1.row, &1.check, &1.passed}) == [
               {11, :row, true},
               {12, :row, true},
               {13, :row, false}
             ]
    end

    test "max_misses lets rows past a failing row count" do
      lenient =
        Path.join([@inbox, "shapes", "invoice.yml"])
        |> YamlElixir.read_from_file!()
        |> Map.put("max_misses", 1)
        |> Shape.from_map!()

      assert {:ok, result} = CSV.classify(path("messy_invoice.csv"), [lenient])

      assert Enum.map(candidate(result, "invoice").rows, &{&1.row, &1.passed}) == [
               {11, true},
               {12, true},
               {13, false},
               {14, true}
             ]
    end

    test "the passing rows are the rows locate yields" do
      result = classify("messy_invoice.csv", ["invoice"])
      invoice = candidate(result, "invoice")

      assert {:ok, table} =
               CSV.locate(path("messy_invoice.csv"), invoice.shape.spec,
                 header_row: invoice.header.row
               )

      assert length(Enum.to_list(table.rows)) == Enum.count(invoice.rows, & &1.passed)
    end

    test "score is header share times row pass rate" do
      assert %Candidate{status: :matched, score: score} =
               "messy_invoice.csv" |> classify(["invoice"]) |> candidate("invoice")

      assert score == 2 / 3

      assert %Candidate{status: :matched, score: 0.75} =
               "invoice_short.csv" |> classify(["invoice"]) |> candidate("invoice")
    end

    test "a header with no rows under it scores on the header alone" do
      result = classify("header_only.csv", ["invoice"])

      assert %Result{verdict: :match} = result
      assert %Candidate{status: :matched, score: 1.0, rows: []} = candidate(result, "invoice")
    end

    test "blank lines inside a table are not scored as rows" do
      shape =
        Shape.from_map!(%{
          "name" => "invoice",
          "header" => %{"columns" => %{"sku" => ["sku"], "total" => ["line total"]}},
          "row" => %{"match" => %{"sku" => "integer", "total" => "number"}}
        })

      source = {:string, "SKU,Line Total\n78632478,3\n,\n , \t\n12319082,5\n"}

      assert {:ok, %Result{verdict: :match} = result} = CSV.classify(source, [shape])
      assert %Candidate{status: :matched, score: 1.0, rows: rows} = candidate(result, "invoice")
      assert Enum.map(rows, & &1.row) == [2, 5]
      assert %Facts{blank_lines: 2} = result.file
    end

    test "the header line with the best rows wins over an earlier one" do
      result = classify("bad_table_then_good.csv", ["invoice"])

      assert %Result{verdict: :match} = result

      invoice = candidate(result, "invoice")

      assert %Candidate{status: :matched, score: 1.0} = invoice
      assert invoice.header.row == 5
      assert Enum.map(invoice.rows, & &1.row) == [6, 7]
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

  describe "facts" do
    test "a file reports what refract can tell about it" do
      result = classify("invoice.csv", ["invoice"])

      assert %Facts{
               path: path,
               size: size,
               lines_sampled: 4,
               above_header: 0,
               blank_lines: 0,
               widths: %{4 => 4},
               format: %{delimiter: ",", line_endings: :lf, bom: false, trailing_newline: true}
             } = result.file

      assert path == path("invoice.csv")
      assert size == File.stat!(path("invoice.csv")).size
    end

    test "lines above the header and blank lines are counted" do
      assert %Facts{above_header: 9, blank_lines: 3, widths: %{8 => 16}} =
               classify("messy_invoice.csv", ["invoice"]).file
    end

    test "no header found means nothing above it" do
      assert %Facts{above_header: nil} = classify("unknown.csv", ["invoice"]).file
    end

    test "ragged lines show in the widths" do
      result = classify("../csv/ragged_rows.csv", ["invoice"])

      assert result.file.widths == %{3 => 2, 2 => 1, 4 => 1}
    end

    test "an empty file" do
      assert %Facts{lines_sampled: 0, blank_lines: 0, widths: widths, above_header: nil} =
               classify("empty.csv", ["invoice"]).file

      assert widths == %{}
    end

    test "the delimiter is detected when not given" do
      result = classify("invoice_semicolon.csv", ["invoice"])

      assert %Result{verdict: :match} = result
      assert %{delimiter: ";", delimiter_source: :detected} = result.file.format
    end

    test "a stream has no path or size" do
      assert {:ok, %Result{file: %Facts{path: nil, size: :unknown}}} =
               CSV.classify({:stream, ["SKU,Item,Kg,Line Total\n"]}, [shape("invoice")])
    end

    test "a stream is never read ahead to detect the delimiter" do
      lines = ["SKU;Item;Kg;Line Total\n", "78632478;apple;2;3\n"]

      assert {:ok, %Result{verdict: :unknown, file: %Facts{format: format}}} =
               CSV.classify({:stream, lines}, [shape("invoice")])

      assert format == %{}

      assert {:ok, %Result{verdict: :match}} =
               CSV.classify({:stream, lines}, [shape("invoice")], separator: ";")
    end

    test "lines alone have no path, size or format" do
      result = Classify.lines([["SKU", "Item", "Kg", "Line Total"]], [shape("invoice")])

      assert %Facts{path: nil, size: nil, lines_sampled: 1, format: format} = result.file
      assert format == %{}
    end
  end

  describe "markers" do
    @plain [
      ["SKU", "Item", "Kg", "Line Total"],
      ["78632478", "apple", "2", "3"]
    ]

    test "markers break a tie between equal shapes" do
      assert %Result{verdict: :match, reason: :markers, shape: %Shape{name: "invoice_au"}} =
               classify("acme_au.csv", ["invoice_nz", "invoice_au"])
    end

    test "a content marker inside the table counts" do
      assert %Result{verdict: :match, reason: :markers, shape: %Shape{name: "invoice_nz"}} =
               classify("acme_nz.csv", ["invoice_au", "invoice_nz"])
    end

    test "a content marker alone breaks a tie" do
      assert %Result{verdict: :match, reason: :markers, shape: %Shape{name: "invoice_au"}} =
               classify("acme_q3.csv", ["invoice_nz", "invoice_au"])
    end

    test "a marker hit beats matching more columns" do
      loose_au =
        Shape.from_map!(%{
          "name" => "invoice_loose_au",
          "markers" => %{"content" => "/tax invoice/i"},
          "header" => %{"columns" => %{"sku" => ["sku"], "total" => ["line total"]}}
        })

      assert {:ok,
              %Result{verdict: :match, reason: :markers, shape: %Shape{name: "invoice_loose_au"}}} =
               CSV.classify(path("acme_au.csv"), [shape("invoice"), loose_au])
    end

    test "no marker hits and equal columns stays ambiguous" do
      assert %Result{verdict: :ambiguous, reason: :within_margin, shape: nil} =
               classify("acme_plain.csv", ["invoice_au", "invoice_nz"])
    end

    test "every candidate reports its markers, file then content" do
      result = classify("acme_au.csv", ["invoice_nz", "invoice_au"])

      assert [
               %Marker{marker: :file, against: "acme_au.csv", passed: true, pattern: file},
               %Marker{marker: :content, against: "Tax Invoice", passed: true, pattern: content}
             ] = candidate(result, "invoice_au").markers

      assert Regex.source(file) == "au"
      assert Regex.source(content) == "tax invoice"

      assert [
               %Marker{marker: :file, against: "acme_au.csv", passed: false},
               %Marker{marker: :content, against: nil, passed: false}
             ] = candidate(result, "invoice_nz").markers
    end

    test "a shape without markers reports none" do
      assert candidate(classify("invoice.csv", ["invoice"]), "invoice").markers == []
    end

    test "markers never override a clear score lead" do
      lines = [["Tax Invoice"], ["SKU", "Item", "Line Total"], ["78632478", "apple", "3"]]

      assert %Result{verdict: :match, reason: nil, shape: %Shape{name: "invoice_loose"}} =
               Classify.lines(lines, [shape("invoice_au"), shape("invoice_loose")],
                 name: "acme_au.csv"
               )
    end

    test "markers never rescue rows that fail" do
      lines = [
        ["Tax Invoice"],
        ["SKU", "Item", "Kg", "Line Total"],
        ["A-100", "apple", "2", "n/a"]
      ]

      assert %Result{verdict: :unknown, reason: :rows_failed} =
               Classify.lines(lines, [shape("invoice_au"), shape("invoice_nz")],
                 name: "acme_au.csv"
               )
    end

    test "lines take a name for the file marker" do
      assert %Result{verdict: :match, reason: :markers, shape: %Shape{name: "invoice_nz"}} =
               Classify.lines(@plain, [shape("invoice_au"), shape("invoice_nz")],
                 name: "acme_nz_q3.csv"
               )
    end

    test "with no name the file marker cannot pass" do
      result = Classify.lines(@plain, [shape("invoice_au"), shape("invoice_nz")])

      assert %Result{verdict: :ambiguous} = result

      assert [%Marker{marker: :file, against: nil, passed: false} | _] =
               candidate(result, "invoice_au").markers
    end

    test "a stream has no name, its content still counts" do
      lines = ["Tax Invoice,,,\n", "SKU,Item,Kg,Line Total\n", "78632478,apple,2,3\n"]

      assert {:ok, %Result{verdict: :match, reason: :markers, shape: %Shape{name: "invoice_au"}}} =
               CSV.classify({:stream, lines}, [shape("invoice_nz"), shape("invoice_au")])
    end

    test "pick first is unchanged and still reports markers" do
      result = classify("acme_au.csv", ["invoice_nz", "invoice_au"], pick: :first)

      assert %Result{verdict: :match, reason: nil, shape: %Shape{name: "invoice_nz"}} = result
      assert [%Marker{passed: true} | _] = candidate(result, "invoice_au").markers
    end

    test "name must be a string" do
      assert_raise ArgumentError, ~r/name/, fn ->
        Classify.lines(@plain, [shape("invoice_au")], name: :acme)
      end
    end
  end

  describe "pick" do
    test "best is ambiguous when two tables each fit a shape, whatever their columns" do
      assert %Result{verdict: :ambiguous, reason: :within_margin} =
               classify("summary_then_invoice.csv", ["invoice", "summary"])
    end

    test "first takes the first line where a shape matches" do
      result = classify("summary_then_invoice.csv", ["invoice", "summary"], pick: :first)

      assert %Result{verdict: :match, reason: nil, shape: %Shape{name: "summary"}} = result
      assert candidate(result, "summary").header.row == 1
    end

    test "first walks past a header whose rows fail" do
      result = classify("bad_table_then_good.csv", ["invoice"], pick: :first)

      assert %Result{verdict: :match} = result
      assert candidate(result, "invoice").header.row == 5
    end

    test "first is never ambiguous, a tie goes to the shape listed first" do
      assert %Result{verdict: :match, shape: %Shape{name: "invoice"}} =
               classify("invoice.csv", ["invoice", "invoice_loose"], pick: :first)

      assert %Result{verdict: :match, shape: %Shape{name: "invoice_loose"}} =
               classify("invoice.csv", ["invoice_loose", "invoice"], pick: :first)
    end

    test "first with no match gives the same result as best" do
      shapes = [shape("invoice"), shape("aws_bill")]

      for file <- ["bad_rows.csv", "stock_list.csv", "unknown.csv", "empty.csv"] do
        assert CSV.classify(path(file), shapes, pick: :first) == CSV.classify(path(file), shapes)
      end
    end

    test "first stops checking once a shape matches" do
      test_pid = self()

      spy =
        Shape.new(
          name: "spy",
          spec:
            Table.spec(
              header: [columns: %{"sku" => ["sku"], "item" => ["item"]}],
              row: [match: %{"sku" => fn value -> send(test_pid, {:checked, value}) end}]
            )
        )

      shapes = [shape("summary"), spy]

      assert {:ok, %Result{shape: %Shape{name: "summary"}}} =
               CSV.classify(path("summary_then_invoice.csv"), shapes, pick: :first)

      refute_received {:checked, _value}

      assert {:ok, _result} = CSV.classify(path("summary_then_invoice.csv"), shapes)
      assert_received {:checked, "78632478"}
    end

    test "unknown pick raises" do
      assert_raise ArgumentError, ~r/pick/, fn ->
        CSV.classify(path("invoice.csv"), [shape("invoice")], pick: :last)
      end
    end
  end

  describe "sources" do
    test "a missing file is an error" do
      assert {:error, :enoent} = CSV.classify(path("missing.csv"), [shape("invoice")])
    end

    test "an unsupported source is an error" do
      assert {:error, {:unsupported_source, :bills}} = CSV.classify(:bills, [shape("invoice")])
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

  describe "unknown options" do
    test "raise" do
      assert_raise ArgumentError, ~r/colour/, fn ->
        CSV.classify(path("invoice.csv"), [shape("invoice")], colour: :blue)
      end
    end
  end

  describe "malformed files" do
    test "a parse error is an error, not a raise" do
      assert {:error, {:parse_error, message}} =
               CSV.classify({:string, "SKU,Item\n78632478,\"apple\n"}, [shape("invoice")])

      assert message =~ "escape character"
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
