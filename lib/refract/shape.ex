defmodule Refract.Shape do
  @moduledoc """
  a shape is a fingerprint for a file. can be provided in code or via yaml file.

  requires `name` and `spec` (a `Refract.Table.Spec`) and optionally `version`
  (default 1) and `markers` (default [])

      Refract.Shape.new(name: "invoice", spec: Refract.Table.spec(header: [columns: %{"sku" => ["sku"]}]))
      Refract.Shape.from_map(%{"name" => "invoice", "header" => %{"columns" => %{"sku" => ["sku"]}}})
      Refract.Shape.load("shapes/invoice.yml")

  a yaml or map shape names custom validators through a registry, `validators:` on
  `from_map/2` and `load/2`, then uses the names in column and field rules

      Refract.Shape.load("shapes/order.yml", validators: %{"abn" => MyApp.Validators.ABN})

  `describe_error/1` reads a `from_map/2` or `load/2` error as text

      iex> Refract.Shape.describe_error({:invalid_value, {"header", 3}})
      "invalid_value header"
  """

  alias Refract.ArgValidator
  alias Refract.Shape.Field
  alias Refract.Shape.FromMap
  alias Refract.Shape.Load
  alias Refract.Table.Spec
  alias Refract.Validate.Rules

  import Refract.String.Utils, only: [blank?: 1]

  @type marker :: {:file, Regex.t()} | {:content, Regex.t()}

  @type t :: %__MODULE__{
          name: String.t(),
          version: pos_integer(),
          spec: Spec.t(),
          markers: [marker()],
          validation: Rules.t(),
          fields: %{String.t() => Field.t()}
        }

  @enforce_keys [:name, :version, :spec]

  defstruct [:name, :version, :spec, :markers, :validation, fields: %{}]

  @type opt ::
          {:name, String.t()}
          | {:spec, Spec.t()}
          | {:version, pos_integer()}
          | {:markers, [marker()]}
          | {:validation, keyword()}
          | {:fields, %{String.t() => keyword()}}

  @type from_map_opt :: {:validators, %{String.t() => module()}}

  @type error ::
          {:not_a_map, term()}
          | {:missing_key, String.t()}
          | {:unknown_key, String.t()}
          | {:invalid_value, {String.t(), term()}}
          | {:invalid_spec, String.t()}
          | {:invalid_shape, String.t()}

  @type load_error ::
          error()
          | {:file_read_error, File.posix()}
          | {:invalid_yaml, String.t()}
          | {:missing_dependency, :yaml_elixir}

  @callback shape() :: t()

  defmacro __using__(_opts) do
    quote do
      @behaviour Refract.Shape
    end
  end

  @spec resolve(t() | module()) :: t()

  def resolve(%__MODULE__{} = shape), do: shape

  def resolve(module) when is_atom(module) do
    if shape_module?(module) do
      module.shape()
    else
      raise ArgumentError, "module #{inspect(module)} does not implement Refract.Shape"
    end
  end

  def resolve(other) do
    raise ArgumentError, "cannot resolve shape from #{inspect(other)}"
  end

  @spec resolve_all([t() | module()]) :: [t()]

  def resolve_all(shapes) when is_list(shapes) and shapes != [], do: Enum.map(shapes, &resolve/1)

  def resolve_all(shapes) do
    raise ArgumentError, "shapes must be a list of at least one shape, got: #{inspect(shapes)}"
  end

  defp shape_module?(module) do
    Code.ensure_loaded?(module) and
      __MODULE__ in (module.module_info(:attributes)
                     |> Keyword.get_values(:behaviour)
                     |> List.flatten())
  end

  @spec new([opt()]) :: t()

  def new(opts) do
    opts =
      Keyword.validate!(opts,
        name: nil,
        spec: nil,
        version: 1,
        markers: [],
        validation: [],
        fields: %{}
      )

    name = Keyword.fetch!(opts, :name)
    spec = Keyword.fetch!(opts, :spec)

    version = Keyword.fetch!(opts, :version)
    markers = Keyword.fetch!(opts, :markers)

    validate_name(name)
    validate_spec(spec)
    ArgValidator.validate_positive_integer!(version, :version)
    validate_markers(markers)

    validation = Rules.new!(Keyword.fetch!(opts, :validation), spec.header.columns)
    fields = fields(Keyword.fetch!(opts, :fields))

    %__MODULE__{
      name: name,
      version: version,
      spec: spec,
      markers: markers,
      validation: validation,
      fields: fields
    }
  end

  defp fields(fields) when is_map(fields),
    do: Map.new(fields, fn {name, opts} -> {field_name(name), Field.new!(opts)} end)

  defp fields(fields) do
    raise ArgumentError, "fields must be a map of names to field options, got: #{inspect(fields)}"
  end

  defp field_name(name) when is_binary(name), do: name

  defp field_name(name) do
    raise ArgumentError, "a field name must be a string, got: #{inspect(name)}"
  end

  @spec from_map(term(), [from_map_opt()]) :: {:ok, t()} | {:error, error()}

  def from_map(map, opts \\ []), do: FromMap.run(map, opts)

  @spec from_map!(term(), [from_map_opt()]) :: t()

  def from_map!(map, opts \\ []) do
    case from_map(map, opts) do
      {:ok, shape} ->
        shape

      {:error, reason} ->
        raise ArgumentError, "cannot create shape from map: #{describe_error(reason)}"
    end
  end

  @spec load(Path.t(), [from_map_opt()]) :: {:ok, t()} | {:error, load_error()}

  def load(path, opts \\ []), do: Load.run(path, opts)

  @spec load!(Path.t(), [from_map_opt()]) :: t()

  def load!(path, opts \\ []) do
    case load(path, opts) do
      {:ok, shape} ->
        shape

      {:error, reason} ->
        raise ArgumentError, "cannot load shape from #{path}: #{describe_error(reason)}"
    end
  end

  @spec describe_error(load_error()) :: String.t()

  def describe_error({:invalid_value, {key, _value}}), do: "invalid_value #{key}"

  def describe_error({reason, detail}) when is_binary(detail) or is_atom(detail),
    do: "#{reason} #{detail}"

  def describe_error({reason, _detail}), do: "#{reason}"

  defp validate_name(name) when is_binary(name) do
    if blank?(name) do
      raise ArgumentError, "name must not be blank"
    end
  end

  defp validate_name(_), do: raise(ArgumentError, "name must be a string")

  defp validate_spec(%Spec{}), do: :ok

  defp validate_spec(_), do: raise(ArgumentError, "spec must be a Refract.Table.Spec")

  @markers_validation_error "markers must be a list of {:file, Regex.t()} or {:content, Regex.t()}"

  defp validate_markers(markers) when is_list(markers) do
    Enum.each(markers, fn
      {:file, regex} when is_struct(regex, Regex) -> :ok
      {:content, regex} when is_struct(regex, Regex) -> :ok
      _ -> raise ArgumentError, @markers_validation_error
    end)
  end

  defp validate_markers(_), do: raise(ArgumentError, @markers_validation_error)
end
