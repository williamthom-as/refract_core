defmodule Refract.DateFormatsTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 10_000

  alias Refract.Classify
  alias Refract.CSV
  alias Refract.Grid
  alias Refract.Shape
  alias Refract.Table

  @dmy {:date, [:dmy, :iso]}

  @columns %{"date" => ["date"], "amount" => ["amount"], "opened_on" => ["opened on"]}

  @statement {:string,
              "Date,Amount,Opened On\n03/10/2026,12.50,01/02/2019\n25/10/2026,-4.00,01/02/2019\n"}

  defp spec(opts \\ []), do: Table.spec([header: [columns: @columns]] ++ opts)

  defp statement(validation),
    do: Shape.new(name: "statement", spec: spec(), validation: validation)

  describe "recognition" do
    defp row_spec(date_rule),
      do: spec(row: [match: %{"date" => date_rule, "amount" => :number}])

    test "a d/m/Y file matches a {:date, formats} row rule" do
      shape = Shape.new(name: "statement", spec: row_spec(@dmy))

      assert {:ok, %Classify.Result{verdict: :match}} = CSV.classify(@statement, [shape])
    end

    test "plain :date stays iso or y/m/d, so 25/10/2026 is not a date" do
      shape = Shape.new(name: "statement", spec: row_spec(:date))

      assert {:ok, %Classify.Result{verdict: :unknown}} = CSV.classify(@statement, [shape])
    end

    test "locate keeps every row" do
      assert {:ok, table} = CSV.locate(@statement, row_spec(@dmy))
      assert [%{"date" => "03/10/2026"}, %{"date" => "25/10/2026"}] = Enum.to_list(table.rows)
    end

    test "unknown formats, no formats, or day first and month first together raise" do
      assert_raise ArgumentError, fn -> row_spec({:date, [:dym]}) end
      assert_raise ArgumentError, fn -> row_spec({:date, []}) end

      assert_raise ArgumentError, ~r/both :dmy and :mdy/, fn ->
        row_spec({:date, [:dmy, :mdy]})
      end
    end

    test "a pattern string is a format" do
      euro = {:string, "Date,Amount,Opened On\n25.10.2026,1.00,x\n"}

      assert {:ok, table} = CSV.locate(euro, row_spec({:date, ["dd.MM.yyyy"]}))
      assert [%{"date" => "25.10.2026"}] = Enum.to_list(table.rows)
    end
  end

  describe "suggest" do
    test "a d/m/Y column is found by its values" do
      shape =
        Shape.new(
          name: "statement",
          spec:
            Table.spec(
              header: [columns: %{"date" => ["date"], "amount" => ["amount"]}],
              row: [match: %{"date" => @dmy, "amount" => :number}]
            )
        )

      source = {:string, "Posted,Amount\n25/10/2026,1.00\n26/10/2026,2.00\n27/10/2026,3.00\n"}

      assert {:ok, %{columns: %{"date" => %{index: 0, via: :values}}}} =
               CSV.suggest(source, shape)
    end
  end

  describe "validation" do
    test "{:date, formats} checks the cell, the issue names the rule as written" do
      shape = statement(columns: %{"date" => [@dmy]})
      bad = {:string, "Date,Amount,Opened On\n25/10/2026,1.00,x\n31/02/2026,1.00,x\n"}

      assert {:ok, %{issues: [%{line: 3, column: "date", rule: @dmy}]}} =
               CSV.validate(bad, shape)
    end

    test "{:datetime, formats} for the date part" do
      shape = statement(columns: %{"date" => [{:datetime, [:dmy]}]})
      source = {:string, "Date,Amount,Opened On\n25/10/2026 09:30,1.00,x\n"}

      assert {:ok, %{valid: true}} = CSV.validate(source, shape)
    end

    test "each column names its own formats" do
      shape = statement(columns: %{"date" => [@dmy], "opened_on" => [{:date, [:mdy]}]})
      source = {:string, "Date,Amount,Opened On\n25/10/2026,1.00,12/31/2019\n"}

      assert {:ok, %{valid: true}} = CSV.validate(source, shape)
    end

    test "bad formats raise when the shape is built" do
      for formats <- [[:dym], [:dmy, :mdy], []] do
        assert_raise ArgumentError, fn -> statement(columns: %{"date" => [{:date, formats}]}) end
      end
    end

    test "field rules take it too" do
      {:ok, grid} = CSV.load({:string, "Opened,25/10/2019\n,\nDate,Amount,Opened On\n"})

      shape =
        Shape.new(
          name: "statement",
          spec: spec(),
          fields: %{"opened" => [label: "opened", rules: [:required, @dmy]]}
        )

      assert {:ok, %{valid: true, fields: %{"opened" => "25/10/2019"}}} =
               Grid.validate(grid, shape)
    end
  end

  describe "Shape.from_map/1" do
    defp map(extra) do
      Map.merge(
        %{
          "name" => "statement",
          "header" => %{"columns" => %{"date" => ["date"], "opened_on" => ["opened on"]}}
        },
        extra
      )
    end

    test "{date: [...]} in row match and validation, names and patterns" do
      map =
        map(%{
          "row" => %{"match" => %{"date" => %{"date" => ["dmy", "iso"]}}},
          "validation" => %{"columns" => %{"opened_on" => [%{"date" => ["dd.MM.yyyy"]}]}}
        })

      assert {:ok, shape} = Shape.from_map(map)
      assert shape.spec.row.match["date"] == {:date, [:dmy, :iso]}
      assert shape.validation.columns["opened_on"] == [{:date, ["dd.MM.yyyy"]}]
    end

    test "bad formats are an invalid value naming where" do
      rule = %{"date" => ["dym"]}

      assert {:error, {:invalid_value, {"validation.columns.opened_on", ^rule}}} =
               Shape.from_map(map(%{"validation" => %{"columns" => %{"opened_on" => [rule]}}}))

      assert {:error, {:invalid_value, {"row.match.date", ^rule}}} =
               Shape.from_map(map(%{"row" => %{"match" => %{"date" => rule}}}))
    end

    @tag :yaml
    test "a block style yaml anchor writes the formats once" do
      yaml = """
      name: statement
      header:
        columns:
          date: [date]
          opened_on: [opened on]
      row:
        match:
          date: &dmy
            date: [dmy, iso]
      validation:
        columns:
          opened_on:
            - required
            - *dmy
      """

      {:ok, map} = YamlElixir.read_from_string(yaml)

      assert {:ok, shape} = Shape.from_map(map)
      assert shape.spec.row.match["date"] == {:date, [:dmy, :iso]}
      assert shape.validation.columns["opened_on"] == [:required, {:date, [:dmy, :iso]}]
    end
  end
end
