defmodule Refract.E2E.ClassifyThenValidateTest do
  use ExUnit.Case, async: true

  @moduletag :e2e
  @moduletag :tmp_dir
  @moduletag timeout: 10_000

  alias Refract.Classify
  alias Refract.Classify.Result
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
            columns: %{
              "sku" => ["sku"],
              "qty" => ["qty"],
              "unit_price" => ["unit price"],
              "line_total" => ["line total"]
            }
          ],
          row: [match: %{"qty" => :number, "line_total" => :number}],
          stop: [:blank]
        ),
      validation: [
        columns: %{
          "sku" => [:required, ~r/^[A-Z]-\d{3}$/],
          "line_total" => [:required, {:max, 10_000}]
        },
        rows: [{:line_total_adds_up, &adds_up?/1}]
      ]
    )
  end

  defp usage do
    Shape.new(
      name: "globex_usage",
      spec:
        Table.spec(
          header: [
            columns: %{
              "account" => ["account"],
              "usage_date" => ["usage date"],
              "cost" => ["cost (usd)"]
            }
          ],
          row: [match: %{"cost" => :number}]
        ),
      validation: [columns: %{"account" => [~r/^\d{12}$/], "usage_date" => [:required, :date]}]
    )
  end

  defp adds_up?(row) do
    {:ok, qty} = Parse.number(row["qty"])
    {:ok, price} = Parse.number(row["unit_price"])
    {:ok, total} = Parse.number(row["line_total"])

    Decimal.eq?(Decimal.mult(qty, price), total)
  end

  defp write!(dir, name, lines),
    do: File.write!(Path.join(dir, name), Enum.join(lines, "\n") <> "\n")

  defp decide({path, {:ok, %Result{verdict: :match} = result}}) do
    {:ok, {reader, reader_opts}} = Reader.for_path(path)
    {:ok, validation} = reader.validate(path, result.shape, reader_opts)

    {Path.basename(path), result.shape.name, outcome(validation)}
  end

  defp decide({path, {:ok, %Result{verdict: verdict}}}),
    do: {Path.basename(path), nil, {:needs_human, verdict}}

  defp decide({path, {:error, reason}}), do: {Path.basename(path), nil, {:needs_human, reason}}

  defp outcome(%{valid: true}), do: :accepted

  defp outcome(%{issues: issues}),
    do: {:needs_human, Enum.map(issues, &{&1.line, &1.column, &1.rule})}

  test "a mixed folder is classified, then every known file validated", %{tmp_dir: dir} do
    title = ["ACME PTY LTD - Tax Invoice,,,", ",,,", "SKU,Qty,Unit Price,Line Total"]

    write!(dir, "acme_0412.csv", title ++ ["A-100,2,12.50,25.00", "B-200,1,99.00,99.00"])

    write!(
      dir,
      "acme_0413.csv",
      title ++ ["A-100,2,12.50,25.00", "C-300,1,12500.00,12500.00", "B-200,4,99.00,369.00"]
    )

    write!(dir, "globex_oct.csv", [
      "Account;Usage Date;Cost (USD)",
      "123456789012;2026-10-01;14.20",
      "123456789013;2026-10-02;8.75"
    ])

    write!(dir, "globex_nov.csv", ["Account;Usage Date;Cost (USD)", "12345;2026-11-01;3.05"])
    write!(dir, "notes.csv", ["name,colour", "fig,purple"])

    {:ok, results} = Classify.folder(dir, [invoice(), usage()])

    assert [
             {"acme_0412.csv", "acme_invoice", :accepted},
             {"acme_0413.csv", "acme_invoice",
              {:needs_human, [{5, "line_total", {:max, 10_000}}, {6, nil, :line_total_adds_up}]}},
             {"globex_nov.csv", "globex_usage", {:needs_human, [{2, "account", %Regex{}}]}},
             {"globex_oct.csv", "globex_usage", :accepted},
             {"notes.csv", nil, {:needs_human, :unknown}}
           ] = Enum.map(results, &decide/1)
  end
end
