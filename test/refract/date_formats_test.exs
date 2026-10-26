defmodule Refract.DateFormatsTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 10_000

  alias Refract.Classify
  alias Refract.CSV
  alias Refract.Grid
  alias Refract.Shape
  alias Refract.Table

  @columns %{"date" => ["date"], "amount" => ["amount"], "opened_on" => ["opened on"]}

  @statement {:string,
              "Date,Amount,Opened On\n03/10/2026,12.50,01/02/2019\n25/10/2026,-4.00,01/02/2019\n"}

  defp spec(opts \\ []), do: Table.spec([header: [columns: @columns]] ++ opts)

  defp statement(validation, opts \\ []),
    do: Shape.new(name: "statement", spec: spec(opts), validation: validation)

  describe "Table.spec/1 dates:" do
    test "a spec keeps its date formats, iso then y/m/d by default" do
      assert spec(dates: [:dmy, :iso]).dates == [:dmy, :iso]
      assert spec().dates == [:iso, :ymd]
    end

    test "a pattern string is a format" do
      assert spec(dates: ["dd.MM.yyyy", :iso]).dates == ["dd.MM.yyyy", :iso]
    end

    test "an unknown format raises" do
      assert_raise ArgumentError, fn -> spec(dates: [:dym]) end
      assert_raise ArgumentError, fn -> spec(dates: []) end
    end

    test "day first and month first together raise, the order would silently decide" do
      assert_raise ArgumentError, ~r/both :dmy and :mdy/, fn -> spec(dates: [:dmy, :mdy]) end
    end
  end

  describe "recognition" do
    defp row_spec(opts),
      do: spec([row: [match: %{"date" => :date, "amount" => :number}]] ++ opts)

    test "a d/m/Y file matches with dates: [:dmy]" do
      shape = Shape.new(name: "statement", spec: row_spec(dates: [:dmy, :iso]))

      assert {:ok, %Classify.Result{verdict: :match}} = CSV.classify(@statement, [shape])
    end

    test "without it, 25/10/2026 is not a date, so the rows fail" do
      shape = Shape.new(name: "statement", spec: row_spec([]))

      assert {:ok, %Classify.Result{verdict: :unknown}} = CSV.classify(@statement, [shape])
    end

    test "locate keeps every row" do
      assert {:ok, table} = CSV.locate(@statement, row_spec(dates: [:dmy]))
      assert [%{"date" => "03/10/2026"}, %{"date" => "25/10/2026"}] = Enum.to_list(table.rows)
    end

    test "a rule level format overrides the spec" do
      us = {:string, "Date,Amount,Opened On\n10/25/2026,1.00,x\n"}
      spec = spec(dates: [:dmy], row: [match: %{"date" => {:date, [:mdy]}}])

      assert {:ok, table} = CSV.locate(us, spec)
      assert [%{"date" => "10/25/2026"}] = Enum.to_list(table.rows)
    end
  end

  describe "validation" do
    test ":date honours the spec's formats, the issue names :date" do
      shape = statement([columns: %{"date" => [:date]}], dates: [:dmy])
      bad = {:string, "Date,Amount,Opened On\n25/10/2026,1.00,x\n31/02/2026,1.00,x\n"}

      assert {:ok, %{issues: [%{line: 3, column: "date", rule: :date}]}} =
               CSV.validate(bad, shape)
    end

    test ":datetime uses them for the date part" do
      shape = statement([columns: %{"date" => [:datetime]}], dates: [:dmy])
      source = {:string, "Date,Amount,Opened On\n25/10/2026 09:30,1.00,x\n"}

      assert {:ok, %{valid: true}} = CSV.validate(source, shape)
    end

    test "date bounds parse the cell with them" do
      shape =
        statement(
          [columns: %{"date" => [{:min, ~D[2026-10-01]}, {:max, ~D[2026-10-31]}]}],
          dates: [:dmy]
        )

      assert {:ok, %{valid: true}} = CSV.validate(@statement, shape)

      late = {:string, "Date,Amount,Opened On\n05/11/2026,1.00,x\n"}

      assert {:ok, %{issues: [%{rule: {:max, ~D[2026-10-31]}}]}} = CSV.validate(late, shape)
    end

    test "a rule level format overrides the spec" do
      shape = statement([columns: %{"opened_on" => [{:date, [:mdy]}]}], dates: [:dmy])
      source = {:string, "Date,Amount,Opened On\n25/10/2026,1.00,12/31/2019\n"}

      assert {:ok, %{valid: true}} = CSV.validate(source, shape)
    end

    test "a rule level format is checked when the shape is built" do
      for formats <- [[:dym], [:dmy, :mdy], []] do
        assert_raise ArgumentError, fn ->
          statement(columns: %{"date" => [{:date, formats}]})
        end
      end
    end

    test "field rules honour them" do
      {:ok, grid} = CSV.load({:string, "Opened,25/10/2019\n,\nDate,Amount,Opened On\n"})

      shape =
        Shape.new(
          name: "statement",
          spec: spec(dates: [:dmy]),
          fields: %{"opened" => [label: "opened", rules: [:required, :date]]}
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

    test "dates: names and patterns" do
      assert {:ok, shape} = Shape.from_map(map(%{"dates" => ["dmy", "dd.MM.yyyy", "iso"]}))
      assert shape.spec.dates == [:dmy, "dd.MM.yyyy", :iso]
    end

    test "a rule level format in row match and validation" do
      map =
        map(%{
          "row" => %{"match" => %{"date" => %{"date" => ["mdy"]}}},
          "validation" => %{"columns" => %{"opened_on" => [%{"date" => ["dmy"]}]}}
        })

      assert {:ok, shape} = Shape.from_map(map)
      assert shape.spec.row.match["date"] == {:date, [:mdy]}
      assert shape.validation.columns["opened_on"] == [{:date, [:dmy]}]
    end

    test "an unknown format is an invalid value" do
      assert {:error, {:invalid_value, {"dates", _value}}} =
               Shape.from_map(map(%{"dates" => ["dym"]}))
    end
  end
end
