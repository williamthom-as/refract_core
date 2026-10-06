defmodule Refract.ShapeTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  alias Refract.Comparable
  alias Refract.Shape
  alias Refract.Table

  @columns %{
    "vendor" => ["vendor", "supplier"],
    "sku" => ["sku", "product code", ~r/^item\s*no/i],
    "total" => ["line total", "amount"]
  }

  defp invoice_spec do
    Table.spec(
      header: [columns: @columns, required: ["sku", "total"], min_matches: 2],
      row: [match: %{"sku" => :integer, "total" => :number}, min_score: 0.5],
      stop: [:blank, {:contains, ~r/^total/i}],
      max_misses: 1
    )
  end

  defp invoice_map do
    %{
      "name" => "invoice",
      "version" => 2,
      "markers" => %{"file" => "/invoice/i", "title" => "/tax invoice/"},
      "header" => %{
        "columns" => %{
          "vendor" => ["vendor", "supplier"],
          "sku" => ["sku", "product code", "/^item\\s*no/i"],
          "total" => ["line total", "amount"]
        },
        "required" => ["sku", "total"],
        "min_matches" => 2
      },
      "row" => %{"match" => %{"sku" => "integer", "total" => "number"}, "min_score" => 0.5},
      "stop" => ["blank", %{"contains" => "/^total/i"}],
      "max_misses" => 1
    }
  end

  defp minimal_map do
    %{"name" => "ids", "header" => %{"columns" => %{"id" => ["id"]}}}
  end

  defp put_in_map(map, path, value), do: put_in(map, Enum.map(path, &Access.key(&1, %{})), value)

  defp delete_in_map(map, path), do: elem(pop_in(map, path), 1)

  describe "new/1" do
    test "builds a shape" do
      spec = invoice_spec()

      shape =
        Shape.new(
          name: "invoice",
          version: 2,
          spec: spec,
          markers: [file: ~r/invoice/i, title: ~r/tax invoice/]
        )

      assert %Shape{name: "invoice", version: 2, spec: ^spec} = shape

      assert Comparable.of(shape.markers) ==
               Comparable.of(file: ~r/invoice/i, title: ~r/tax invoice/)
    end

    test "version defaults to 1 and markers to none" do
      assert %Shape{version: 1, markers: []} = Shape.new(name: "ids", spec: invoice_spec())
    end

    test "name is required" do
      assert_raise ArgumentError, ~r/name/, fn -> Shape.new(spec: invoice_spec()) end
    end

    test "name must be a non empty string" do
      assert_raise ArgumentError, ~r/name/, fn ->
        Shape.new(name: :invoice, spec: invoice_spec())
      end

      assert_raise ArgumentError, ~r/name/, fn -> Shape.new(name: "", spec: invoice_spec()) end
    end

    test "spec is required and must be a table spec" do
      assert_raise ArgumentError, ~r/spec/, fn -> Shape.new(name: "ids") end
      assert_raise ArgumentError, ~r/spec/, fn -> Shape.new(name: "ids", spec: [header: []]) end
    end

    test "version must be a positive integer" do
      assert_raise ArgumentError, ~r/version/, fn ->
        Shape.new(name: "ids", spec: invoice_spec(), version: 0)
      end

      assert_raise ArgumentError, ~r/version/, fn ->
        Shape.new(name: "ids", spec: invoice_spec(), version: "2")
      end
    end

    test "markers are file and title regexes" do
      assert_raise ArgumentError, ~r/marker/, fn ->
        Shape.new(name: "ids", spec: invoice_spec(), markers: [sheet: ~r/x/])
      end

      assert_raise ArgumentError, ~r/marker/, fn ->
        Shape.new(name: "ids", spec: invoice_spec(), markers: [file: "invoice"])
      end
    end

    test "unknown options raise" do
      assert_raise ArgumentError, fn ->
        Shape.new(name: "ids", spec: invoice_spec(), transform: & &1)
      end
    end
  end

  describe "from_map/1" do
    test "builds the same shape as new" do
      expected =
        Shape.new(
          name: "invoice",
          version: 2,
          spec: invoice_spec(),
          markers: [file: ~r/invoice/i, title: ~r/tax invoice/]
        )

      assert {:ok, shape} = Shape.from_map(invoice_map())
      assert Comparable.of(shape) == Comparable.of(expected)
    end

    test "a minimal map takes the defaults" do
      expected = Shape.new(name: "ids", spec: Table.spec(header: [columns: %{"id" => ["id"]}]))

      assert {:ok, shape} = Shape.from_map(minimal_map())
      assert Comparable.of(shape) == Comparable.of(expected)
    end

    test "a single alias needs no list" do
      map = put_in_map(minimal_map(), ["header", "columns", "id"], "id")

      assert {:ok, shape} = Shape.from_map(map)
      assert shape.spec.header.columns == %{"id" => ["id"]}
    end

    test "slashes make a regex with flags" do
      map = put_in_map(minimal_map(), ["header", "columns", "id"], ["/^ID\\d+$/i"])

      assert {:ok, shape} = Shape.from_map(map)
      assert {:ok, %{"id" => 0}} = Table.match_header(shape.spec, ["id42"])
    end

    test "date and datetime rules" do
      for name <- ["date", "datetime"] do
        map = put_in_map(minimal_map(), ["row"], %{"match" => %{"id" => name}})

        assert {:ok, shape} = Shape.from_map(map)
        assert shape.spec.row.match == %{"id" => String.to_existing_atom(name)}
      end
    end

    test "regex rule" do
      map = put_in_map(minimal_map(), ["row"], %{"match" => %{"id" => "/^i-/"}})

      assert {:ok, shape} = Shape.from_map(map)
      assert :ok = Table.match_row(shape.spec, %{"id" => "i-0abc"})
      assert {:error, _} = Table.match_row(shape.spec, %{"id" => "x-0abc"})
    end

    test "missing name" do
      assert {:error, {:missing_key, "name"}} = Shape.from_map(Map.delete(minimal_map(), "name"))
    end

    test "missing header columns" do
      map = delete_in_map(minimal_map(), ["header", "columns"])

      assert {:error, {:missing_key, "header.columns"}} = Shape.from_map(map)
    end

    test "unknown keys are named" do
      assert {:error, {:unknown_key, "transform"}} =
               Shape.from_map(Map.put(minimal_map(), "transform", "x"))

      assert {:error, {:unknown_key, "header.colums"}} =
               Shape.from_map(put_in_map(minimal_map(), ["header", "colums"], %{}))
    end

    test "unknown rule name" do
      map = put_in_map(minimal_map(), ["row"], %{"match" => %{"id" => "money"}})

      assert {:error, {:invalid_value, {"row.match.id", "money"}}} = Shape.from_map(map)
    end

    test "unknown stop" do
      map = Map.put(minimal_map(), "stop", ["never"])

      assert {:error, {:invalid_value, {"stop", "never"}}} = Shape.from_map(map)
    end

    test "aliases must be strings" do
      map = put_in_map(minimal_map(), ["header", "columns", "id"], ["id", false])

      assert {:error, {:invalid_value, {"header.columns.id", false}}} = Shape.from_map(map)
    end

    test "a bad regex is named" do
      map = put_in_map(minimal_map(), ["header", "columns", "id"], ["/[/"])

      assert {:error, {:invalid_value, {"header.columns.id", "/[/"}}} = Shape.from_map(map)
    end

    test "markers must be regexes" do
      map = Map.put(minimal_map(), "markers", %{"file" => "invoice"})

      assert {:error, {:invalid_value, {"markers.file", "invoice"}}} = Shape.from_map(map)
    end

    test "name must be a string" do
      assert {:error, {:invalid_value, {"name", 12}}} =
               Shape.from_map(Map.put(minimal_map(), "name", 12))
    end

    test "spec level problems" do
      map = put_in_map(minimal_map(), ["row"], %{"match" => %{"nope" => "integer"}})

      assert {:error, {:invalid_spec, message}} = Shape.from_map(map)
      assert message =~ "nope"
    end

    test "not a map" do
      assert {:error, {:not_a_map, nil}} = Shape.from_map(nil)
    end
  end

  describe "from_map!/1" do
    test "returns the shape" do
      assert %Shape{name: "ids"} = Shape.from_map!(minimal_map())
    end

    test "raises naming the key" do
      assert_raise ArgumentError, ~r/header\.colums/, fn ->
        Shape.from_map!(put_in_map(minimal_map(), ["header", "colums"], %{}))
      end
    end
  end
end
