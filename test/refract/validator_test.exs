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

  @registry %{"abn" => ABN, "prefix" => Prefix}

  @shape_files Path.expand("../fixtures/shape_files", __DIR__)

  defp shape_file(name), do: Path.join(@shape_files, name)

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

  defp order_map(columns, fields \\ %{}) do
    %{
      "name" => "order",
      "header" => %{
        "columns" => %{"supplier_abn" => ["supplier abn"], "po" => ["po"], "qty" => ["qty"]}
      },
      "validation" => %{"columns" => columns},
      "fields" => fields
    }
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

  describe "Shape.from_map/2 validators:" do
    test "a registered name is the bare validator, in column and field rules" do
      map =
        order_map(
          %{"supplier_abn" => ["required", "abn"]},
          %{"abn" => %{"at" => "B1", "rules" => ["abn"]}}
        )

      assert {:ok, shape} = Shape.from_map(map, validators: @registry)
      assert shape.validation.columns["supplier_abn"] == [:required, ABN]
      assert shape.fields["abn"].rules == [ABN]
    end

    test "a registered name with options is the validator with a keyword list" do
      map = order_map(%{"po" => [%{"prefix" => %{"prefix" => "PO-"}}]})

      assert {:ok, shape} = Shape.from_map(map, validators: @registry)
      assert shape.validation.columns["po"] == [{Prefix, [prefix: "PO-"]}]
    end

    test "empty options are an empty keyword list" do
      map = order_map(%{"supplier_abn" => [%{"abn" => %{}}]})

      assert {:ok, shape} = Shape.from_map(map, validators: @registry)
      assert shape.validation.columns["supplier_abn"] == [{ABN, []}]
    end

    test "a shape from a map validates with its validators" do
      map = order_map(%{"supplier_abn" => ["abn"], "po" => [%{"prefix" => %{"prefix" => "PO-"}}]})
      shape = Shape.from_map!(map, validators: @registry)
      csv = {:string, "Supplier ABN,PO,Qty\n#{@invalid_abn},X-1,2\n"}

      assert {:ok, %{issues: issues}} = CSV.validate(csv, shape)

      assert [
               %{column: "po", rule: {Prefix, [prefix: "PO-"]}},
               %{column: "supplier_abn", rule: ABN}
             ] =
               Enum.sort_by(issues, & &1.column)
    end

    test "an unregistered name is an invalid value naming where" do
      map = order_map(%{"supplier_abn" => ["abn"]})

      assert {:error, {:invalid_value, {"validation.columns.supplier_abn", "abn"}}} =
               Shape.from_map(map)

      assert {:error, {:invalid_value, {"validation.columns.supplier_abn", "abn"}}} =
               Shape.from_map(map, validators: %{"prefix" => Prefix})
    end

    test "an unregistered name in a field rule names the field" do
      map = order_map(%{}, %{"abn" => %{"at" => "B1", "rules" => ["abn"]}})

      assert {:error, {:invalid_value, {"fields.abn.rules", "abn"}}} = Shape.from_map(map)
    end

    test "options must be a map of option names the validator knows" do
      for options <- ["PO-", ["PO-"], %{"no_such_validator_option" => "PO-"}] do
        rule = %{"prefix" => options}

        assert {:error, {:invalid_value, {"validation.columns.po", ^rule}}} =
                 Shape.from_map(order_map(%{"po" => [rule]}), validators: @registry)
      end
    end

    test "registered names do not reach recognition rules" do
      map = Map.put(order_map(%{}), "row", %{"match" => %{"supplier_abn" => "abn"}})

      assert {:error, {:invalid_value, {"row.match.supplier_abn", "abn"}}} =
               Shape.from_map(map, validators: @registry)
    end

    test "a registry entry that is not a validator raises, used or not" do
      for module <- [NotAValidator, MyApp.Validators.Missing] do
        assert_raise ArgumentError, ~r/checksum/, fn ->
          Shape.from_map(order_map(%{}), validators: %{"checksum" => module})
        end
      end
    end

    test "a registry name that shadows a built in rule raises" do
      for name <- ~w(required integer number date datetime min max in) do
        assert_raise ArgumentError, ~r/#{name}/, fn ->
          Shape.from_map(order_map(%{}), validators: %{name => ABN})
        end
      end
    end

    test "registry names must be strings" do
      assert_raise ArgumentError, ~r/validators/, fn ->
        Shape.from_map(order_map(%{}), validators: %{abn: ABN})
      end
    end

    test "unknown options raise" do
      assert_raise ArgumentError, ~r/registry/, fn ->
        Shape.from_map(order_map(%{}), registry: @registry)
      end
    end
  end

  describe "Shape.load/2 validators:" do
    @describetag :yaml

    test "a yaml shape uses registered validators" do
      assert {:ok, shape} = Shape.load(shape_file("validated.yml"), validators: @registry)
      assert shape.validation.columns["supplier_abn"] == [:required, ABN]
      assert shape.validation.columns["po"] == [{Prefix, [prefix: "PO-"]}]
      assert shape.fields["abn"].rules == [ABN]
    end

    test "without the registry the name is unknown" do
      assert {:error, {:invalid_value, {"validation.columns.po", %{"prefix" => _options}}}} =
               Shape.load(shape_file("validated.yml"))
    end

    test "load! takes validators too" do
      assert %{name: "order"} = Shape.load!(shape_file("validated.yml"), validators: @registry)

      assert_raise ArgumentError, ~r/validation.columns.po/, fn ->
        Shape.load!(shape_file("validated.yml"))
      end
    end
  end
end
