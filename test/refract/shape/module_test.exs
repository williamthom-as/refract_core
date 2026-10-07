defmodule Refract.Shape.ModuleTest.Invoice do
  use Refract.Shape

  @impl Refract.Shape
  def shape do
    Refract.Shape.new(
      name: "invoice",
      spec:
        Refract.Table.spec(
          header: [columns: %{"sku" => ["sku"], "total" => ["line total", "amount"]}],
          row: [match: %{"sku" => &String.starts_with?(&1, "SKU-")}]
        ),
      markers: [file: ~r/invoice/i]
    )
  end
end

defmodule Refract.Shape.ModuleTest.FromYaml do
  use Refract.Shape

  @impl Refract.Shape
  def shape,
    do: Refract.Shape.load!(Path.expand("../../fixtures/shape_files/invoice.yml", __DIR__))
end

defmodule Refract.Shape.ModuleTest.NotAShape do
  def shape, do: :nope
end

defmodule Refract.Shape.ModuleTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  alias Refract.Comparable
  alias Refract.Shape
  alias Refract.Shape.ModuleTest.FromYaml
  alias Refract.Shape.ModuleTest.Invoice
  alias Refract.Shape.ModuleTest.NotAShape
  alias Refract.Table

  @shape_files Path.expand("../../fixtures/shape_files", __DIR__)

  describe "use Refract.Shape" do
    test "declares the behaviour" do
      behaviours =
        Invoice.module_info(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()

      assert Shape in behaviours
    end

    test "shape returns the struct" do
      assert %Shape{name: "invoice", version: 1} = Invoice.shape()
    end

    test "fn rules work in a module shape" do
      spec = Invoice.shape().spec

      assert :ok = Table.match_row(spec, %{"sku" => "SKU-1", "total" => "3"})
      assert {:error, _} = Table.match_row(spec, %{"sku" => "1", "total" => "3"})
    end

    test "a module can load its shape from yaml" do
      expected = Shape.load!(Path.join(@shape_files, "invoice.yml"))

      assert Comparable.of(FromYaml.shape()) == Comparable.of(expected)
    end
  end

  describe "resolve/1" do
    test "a shape module gives its shape" do
      assert Comparable.of(Shape.resolve(Invoice)) == Comparable.of(Invoice.shape())
    end

    test "a shape gives itself" do
      shape = Invoice.shape()

      assert Shape.resolve(shape) == shape
    end

    test "a module without the behaviour raises naming it" do
      assert_raise ArgumentError, ~r/NotAShape/, fn -> Shape.resolve(NotAShape) end
    end

    test "a module that does not exist raises naming it" do
      assert_raise ArgumentError, ~r/Nope\.Missing/, fn -> Shape.resolve(Nope.Missing) end
    end

    test "anything else raises" do
      assert_raise ArgumentError, fn -> Shape.resolve("invoice") end
      assert_raise ArgumentError, fn -> Shape.resolve(%{name: "invoice"}) end
    end
  end
end
