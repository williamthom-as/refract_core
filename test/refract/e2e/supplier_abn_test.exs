defmodule Refract.E2E.SupplierAbnTest do
  use ExUnit.Case, async: true

  @moduletag :e2e
  @moduletag timeout: 10_000

  alias Refract.CSV
  alias Refract.Shape
  alias Refract.Table
  alias Refract.TestValidators.ABN

  @columns %{
    "sku" => ["sku"],
    "qty" => ["qty"],
    "unit_price" => ["unit price"],
    "line_total" => ["line total"]
  }

  defp invoice do
    Shape.new(
      name: "acme_invoice",
      spec: Table.spec(header: [columns: @columns], stop: [:blank]),
      validation: [columns: %{"line_total" => [:required, {:max, 10_000}]}],
      fields: %{
        "invoice_no" => [label: "invoice no", rules: [:required]],
        "supplier_abn" => [label: "abn", rules: [:required, ABN]]
      }
    )
  end

  defp yaml_invoice do
    Shape.from_map!(
      %{
        "name" => "acme_invoice",
        "header" => %{"columns" => @columns},
        "stop" => ["blank"],
        "validation" => %{"columns" => %{"line_total" => ["required", %{"max" => 10_000}]}},
        "fields" => %{
          "invoice_no" => %{"label" => "invoice no", "rules" => ["required"]},
          "supplier_abn" => %{"label" => "abn", "rules" => ["required", "abn"]}
        }
      },
      validators: %{"abn" => ABN}
    )
  end

  defp invoice_csv(abn) do
    {:string,
     """
     ACME PTY LTD - Tax Invoice,,,
     Invoice No,INV-1001,,
     ABN,#{abn},,
     SKU,Qty,Unit Price,Line Total
     A-100,3,12.50,37.50
     B-200,1,99.00,99.00
     ,,,
     Total,,,136.50
     """}
  end

  for {kind, shape} <- [elixir: :invoice, yaml: :yaml_invoice] do
    describe "an acme invoice from an #{kind} shape" do
      test "a valid supplier abn passes" do
        assert {:ok, %{valid: true, rows: 2, fields: fields}} =
                 CSV.validate(invoice_csv("51 824 753 556"), unquote(shape)())

        assert fields["supplier_abn"] == "51 824 753 556"
      end

      test "a bad checksum is an issue naming the field and the validator" do
        assert {:ok, %{valid: false, issues: [issue]}} =
                 CSV.validate(invoice_csv("51 824 753 557"), unquote(shape)())

        assert %{field: "supplier_abn", line: 3, rule: ABN, column: nil} = issue
      end

      test "a missing abn fails required, not the validator" do
        assert {:ok, %{valid: false, issues: [issue]}} =
                 CSV.validate(invoice_csv(""), unquote(shape)())

        assert %{field: "supplier_abn", line: 3, rule: :required} = issue
      end
    end
  end
end
