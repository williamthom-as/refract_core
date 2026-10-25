defmodule Refract.E2E.InvoiceTotalsTest do
  use ExUnit.Case, async: true

  @moduletag :e2e
  @moduletag :tmp_dir
  @moduletag timeout: 10_000

  alias Refract.Classify
  alias Refract.Classify.Result
  alias Refract.CSV
  alias Refract.Parse
  alias Refract.Reader
  alias Refract.Shape
  alias Refract.Table

  defp invoice do
    Shape.new(
      name: "acme_invoice",
      markers: [content: ~r/acme pty ltd/i],
      spec:
        Table.spec(
          header: [
            columns: %{"sku" => ["sku"], "qty" => ["qty"], "line_total" => ["line total"]}
          ],
          row: [match: %{"qty" => :number, "line_total" => :number}],
          stop: [:blank]
        ),
      validation: [
        columns: %{"line_total" => [:required, {:max, 10_000}]},
        document: [{:total_matches_lines, &total_matches_lines?/1}]
      ],
      fields: %{
        "invoice_no" => [label: "invoice no", rules: [:required, ~r/^INV-\d+$/]],
        "total" => [label: "total", rules: [:required, :number]]
      }
    )
  end

  defp total_matches_lines?(%{fields: %{"total" => total}, rows: rows}) do
    rows
    |> Enum.map(&Parse.number!(&1["line_total"]))
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
    |> Decimal.eq?(Parse.number!(total))
  end

  defp write!(dir, name, invoice_no, lines, total) do
    content =
      [
        "ACME PTY LTD - Tax Invoice,,",
        "Invoice No,#{invoice_no},",
        ",,",
        "SKU,Qty,Line Total"
      ] ++ lines ++ [",,", "Total,,#{total}"]

    File.write!(Path.join(dir, name), Enum.join(content, "\n") <> "\n")
  end

  defp decide({path, {:ok, %Result{verdict: :match} = result}}) do
    {:ok, {reader, reader_opts}} = Reader.for_path(path)
    {:ok, validation} = reader.validate(path, result.shape, reader_opts)

    {Path.basename(path), outcome(validation)}
  end

  defp outcome(%{valid: true, fields: fields}), do: {:accepted, fields["invoice_no"]}

  defp outcome(%{issues: issues}),
    do: {:needs_human, Enum.map(issues, &{&1.line, &1.column || &1.field, &1.rule})}

  test "a folder of invoices: totals checked against their lines", %{tmp_dir: dir} do
    write!(dir, "acme_0412.csv", "INV-1001", ["A-100,3,37.50", "B-200,1,99.00"], "136.50")
    write!(dir, "acme_0413.csv", "INV-1002", ["A-100,2,25.00", "B-200,4,396.00"], "412.00")

    write!(
      dir,
      "acme_0414.csv",
      "1003",
      ["A-100,2,25.00", "C-300,1,12500.00"],
      "12525.00"
    )

    {:ok, results} = Classify.folder(dir, [invoice()])

    assert [
             {"acme_0412.csv", {:accepted, "INV-1001"}},
             {"acme_0413.csv", {:needs_human, [{nil, nil, :total_matches_lines}]}},
             {"acme_0414.csv",
              {:needs_human,
               [
                 {2, "invoice_no", %Regex{}},
                 {6, "line_total", {:max, 10_000}}
               ]}}
           ] = Enum.map(results, &decide/1)
  end

  test "a total that is not a number fails its field rule and the document rule", %{
    tmp_dir: dir
  } do
    write!(dir, "acme_0415.csv", "INV-1005", ["A-100,3,37.50"], "n/a")
    path = Path.join(dir, "acme_0415.csv")

    assert {:ok, %{valid: false, issues: issues}} = CSV.validate(path, invoice())

    assert [%{field: "total", line: 7, rule: :number}, %{rule: :total_matches_lines, line: nil}] =
             issues
  end
end
