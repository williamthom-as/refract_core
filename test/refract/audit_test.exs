defmodule Refract.AuditTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag timeout: 10_000

  alias Refract.Classify.Result
  alias Refract.CSV
  alias Refract.Shape
  alias Refract.Table
  alias Refract.TestValidators.ABN
  alias Refract.Validate

  defp invoice do
    Shape.new(
      name: "acme_invoice",
      version: 2,
      markers: [content: ~r/acme pty ltd/i],
      spec:
        Table.spec(
          header: [columns: %{"sku" => ["sku"], "line_total" => ["line total"]}],
          row: [match: %{"line_total" => :number}],
          stop: [:blank]
        ),
      validation: [
        columns: %{"sku" => [~r/^[A-Z]-\d{3}$/], "line_total" => [{:max, 10_000}]},
        document: [{:total_matches_lines, fn _document -> false end}]
      ],
      fields: %{"supplier_abn" => [label: "abn", rules: [ABN]]}
    )
  end

  defp usage do
    Shape.new(
      name: "globex_usage",
      spec: Table.spec(header: [columns: %{"account" => ["account"], "cost" => ["cost"]}])
    )
  end

  defp invoice_file!(dir) do
    path = Path.join(dir, "acme_0413.csv")

    File.write!(path, """
    ACME PTY LTD - Tax Invoice,,
    ABN,51 824 753 557,
    SKU,Line Total,Region
    A-100,25.00,au
    x-1,12500.00,au
    """)

    path
  end

  defp plain?(value) when is_struct(value), do: false
  defp plain?(value) when is_map(value), do: Enum.all?(value, &plain?/1)
  defp plain?({key, value}) when is_atom(key) or is_binary(key), do: plain?(value)
  defp plain?(value) when is_list(value), do: Enum.all?(value, &plain?/1)
  defp plain?(value) when is_binary(value) or is_number(value) or is_atom(value), do: true
  defp plain?(_value), do: false

  describe "Classify.Result.to_map/1" do
    test "a match: the verdict, the shape, the file and why", %{tmp_dir: dir} do
      path = invoice_file!(dir)
      {:ok, result} = CSV.classify(path, [invoice(), usage()])

      assert %{
               path: ^path,
               verdict: :match,
               reason: nil,
               shape: %{name: "acme_invoice", version: 2}
             } = Result.to_map(result)
    end

    test "every candidate with its status, score, header line and markers", %{tmp_dir: dir} do
      {:ok, result} = CSV.classify(invoice_file!(dir), [invoice(), usage()])

      assert %{candidates: candidates} = Result.to_map(result)

      assert [
               %{
                 shape: "acme_invoice",
                 status: :matched,
                 score: 1.0,
                 header_line: 3,
                 markers: [%{marker: :content, pattern: "~r/acme pty ltd/i", passed: true}]
               },
               %{shape: "globex_usage", status: :no_header, score: +0.0, header_line: nil}
             ] = Enum.sort_by(candidates, & &1.shape)
    end

    test "drift lists cells as index and text", %{tmp_dir: dir} do
      {:ok, result} = CSV.classify(invoice_file!(dir), [invoice()])

      assert %{drift: %{missing: [], extra: [[2, "Region"]], others: %{}}} =
               Result.to_map(result)
    end

    test "the reader by module name", %{tmp_dir: dir} do
      {:ok, result} = CSV.classify(invoice_file!(dir), [invoice()], separator: ",")

      assert %{reader: "Refract.CSV"} = Result.to_map(result)
      assert %{reader: nil} = result |> Map.put(:reader, nil) |> Result.to_map()
    end

    test "an unknown file has no shape and no drift" do
      {:ok, result} = CSV.classify({:string, "name,colour\nfig,purple\n"}, [invoice()])

      assert %{verdict: :unknown, reason: :no_header, shape: nil, drift: nil, path: nil} =
               Result.to_map(result)
    end

    test "the map is plain data, no structs, regexes, functions or tuples", %{tmp_dir: dir} do
      {:ok, result} = CSV.classify(invoice_file!(dir), [invoice(), usage()])

      assert plain?(Result.to_map(result))
    end
  end

  describe "Validate.Result.to_map/1" do
    test "valid, rows, field values and issues with rules as text", %{tmp_dir: dir} do
      {:ok, validation} = CSV.validate(invoice_file!(dir), invoice())

      assert %{
               valid: false,
               rows: 2,
               fields: %{"supplier_abn" => "51 824 753 557"},
               issues: [
                 %{
                   field: "supplier_abn",
                   line: 2,
                   column: nil,
                   rule: "Refract.TestValidators.ABN",
                   value: nil
                 },
                 %{line: 5, column: "line_total", field: nil, rule: "{:max, 10000}"},
                 %{line: 5, column: "sku", rule: "~r/^[A-Z]-\\d{3}$/"},
                 %{line: nil, column: nil, field: nil, rule: ":total_matches_lines"}
               ]
             } = Validate.Result.to_map(validation)
    end

    test "issue values appear only when validated with values: true", %{tmp_dir: dir} do
      {:ok, validation} = CSV.validate(invoice_file!(dir), invoice(), values: true)

      assert %{issues: [_abn, %{column: "line_total", value: "12500.00"} | _rest]} =
               Validate.Result.to_map(validation)
    end

    test "typed cells become text" do
      validation = %Validate.Result{
        valid: false,
        rows: 1,
        fields: %{"total" => Decimal.new("136.50"), "issued_on" => ~D[2026-10-05], "po" => nil},
        issues: [
          %Validate.Issue{line: 4, column: "qty", rule: {:min, 1}, value: Decimal.new("0")}
        ]
      }

      assert %{
               fields: %{"total" => "136.50", "issued_on" => "2026-10-05", "po" => nil},
               issues: [%{rule: "{:min, 1}", value: "0"}]
             } = Validate.Result.to_map(validation)
    end

    test "a recognition issue names its rule", %{tmp_dir: dir} do
      path = Path.join(dir, "loose.csv")
      File.write!(path, "SKU,Line Total\nA-100,n/a\n")

      shape =
        Shape.new(
          name: "loose",
          spec:
            Table.spec(
              header: [columns: %{"sku" => ["sku"], "line_total" => ["line total"]}],
              row: [match: %{"line_total" => :number}]
            )
        )

      {:ok, validation} = CSV.validate(path, shape)

      assert %{issues: [%{column: "line_total", rule: "{:recognition, :number}"}]} =
               Validate.Result.to_map(validation)
    end

    test "the map is plain data", %{tmp_dir: dir} do
      {:ok, validation} = CSV.validate(invoice_file!(dir), invoice(), values: true)

      assert plain?(Validate.Result.to_map(validation))
    end
  end
end
