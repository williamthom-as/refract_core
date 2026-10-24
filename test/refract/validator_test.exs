defmodule Refract.ValidatorTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 10_000

  alias Refract.CSV
  alias Refract.Grid
  alias Refract.Shape
  alias Refract.Table
  alias Refract.TestValidators.ABN
  alias Refract.TestValidators.NotAValidator
  alias Refract.TestValidators.Prefix
  alias Refract.TestValidators.Raising
  alias Refract.Validate

  @valid_abn "51 824 753 556"
  @invalid_abn "51 824 753 557"

  defp spec do
    Table.spec(
      header: [columns: %{"supplier_abn" => ["supplier abn"], "po" => ["po"], "qty" => ["qty"]}]
    )
  end

  defp shape(columns, fields \\ %{}),
    do: Shape.new(name: "order", spec: spec(), validation: [columns: columns], fields: fields)

  defp issues(rows, shape) do
    for {:invalid, _row, issues} <- rows |> Validate.rows(shape) |> Enum.to_list(),
        issue <- issues,
        do: issue
  end

  defp row(overrides),
    do: Map.merge(%{"supplier_abn" => @valid_abn, "po" => "PO-1", "qty" => "2"}, overrides)

  describe "validator modules as column rules" do
    test "a validator checks a column" do
      shape = shape(%{"supplier_abn" => [{ABN, []}]})

      assert issues([row(%{})], shape) == []

      assert [%{line: 1, column: "supplier_abn", rule: {ABN, []}}] =
               issues([row(%{"supplier_abn" => @invalid_abn})], shape)
    end

    test "the bare module is a validator with no options" do
      shape = shape(%{"supplier_abn" => [ABN]})

      assert [%{column: "supplier_abn", rule: ABN}] =
               issues([row(%{"supplier_abn" => @invalid_abn})], shape)
    end

    test "options pass through to the validator" do
      shape = shape(%{"po" => [{Prefix, prefix: "PO-"}]})

      assert issues([row(%{"po" => "PO-7"})], shape) == []

      assert [%{column: "po", rule: {Prefix, [prefix: "PO-"]}}] =
               issues([row(%{"po" => "X-7"})], shape)
    end

    test "a validator that raises fails its rule" do
      assert [%{column: "po", rule: Raising}] = issues([row(%{})], shape(%{"po" => [Raising]}))
    end

    test "a blank cell skips a validator, :required still catches it" do
      assert issues([row(%{"supplier_abn" => ""})], shape(%{"supplier_abn" => [ABN]})) == []

      assert [%{column: "supplier_abn", rule: :required}] =
               issues(
                 [row(%{"supplier_abn" => ""})],
                 shape(%{"supplier_abn" => [:required, ABN]})
               )
    end

    test "a column reports the first rule that fails, validators in order with the rest" do
      shape = shape(%{"supplier_abn" => [{:in, [@invalid_abn]}, ABN]})

      assert [%{rule: ABN}] = issues([row(%{"supplier_abn" => @invalid_abn})], shape)
    end

    test "built in rules keep working beside validators" do
      shape =
        shape(%{
          "qty" => [{:min, 1}, {:in, ["1", "2", "3"]}],
          "po" => [{:known_po, &String.starts_with?(&1, "PO")}, {Prefix, prefix: "PO-"}]
        })

      assert issues([row(%{})], shape) == []
      assert [%{column: "qty", rule: {:min, 1}}] = issues([row(%{"qty" => "0"})], shape)
      assert [%{column: "po", rule: :known_po}] = issues([row(%{"po" => "X-1"})], shape)
    end

    test "a reader validates with validators too" do
      csv = {:string, "Supplier ABN,PO,Qty\n#{@valid_abn},PO-1,2\n#{@invalid_abn},PO-2,1\n"}

      assert {:ok, %{issues: [%{line: 3, column: "supplier_abn", rule: ABN}]}} =
               CSV.validate(csv, shape(%{"supplier_abn" => [ABN]}))
    end
  end

  describe "validator modules as field rules" do
    test "a validator checks a field" do
      form = "Supplier ABN,#{@invalid_abn}\n,\nSupplier ABN,PO,Qty\n#{@valid_abn},PO-1,2\n"
      {:ok, grid} = CSV.load({:string, form})

      shape = shape(%{}, %{"abn" => [at: "B1", rules: [ABN]]})

      assert {:ok, %{issues: [%{field: "abn", line: 1, rule: ABN}]}} = Grid.validate(grid, shape)
    end
  end

  describe "checked when the shape is built" do
    test "a module that is not a validator raises" do
      for rule <- [NotAValidator, {NotAValidator, []}] do
        assert_raise ArgumentError, ~r/rule/, fn -> shape(%{"po" => [rule]}) end
      end
    end

    test "a module that does not exist raises" do
      for rule <- [MyApp.Validators.Missing, {MyApp.Validators.Missing, []}] do
        assert_raise ArgumentError, ~r/rule/, fn -> shape(%{"po" => [rule]}) end
      end
    end

    test "validator options must be a keyword list" do
      assert_raise ArgumentError, ~r/rule/, fn -> shape(%{"po" => [{Prefix, "PO-"}]}) end
    end

    test "field rules are checked the same way" do
      assert_raise ArgumentError, ~r/rule/, fn ->
        shape(%{}, %{"abn" => [label: "abn", rules: [NotAValidator]]})
      end
    end
  end
end
