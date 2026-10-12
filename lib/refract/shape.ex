defmodule Refract.Shape do
  @moduledoc """
  a shape is a fingerprint for a file. can be provided in code or via yaml file.

  requires `name` and `spec` (a `Refract.Table.Spec`) and optionally `version`
  (default 1) and `markers` (default [])

      Refract.Shape.new(name: "invoice", spec: Refract.Table.spec(header: [columns: %{"sku" => ["sku"]}]))
      Refract.Shape.from_map(%{"name" => "invoice", "header" => %{"columns" => %{"sku" => ["sku"]}}})
      Refract.Shape.load("shapes/invoice.yml")
  """

  alias Refract.Shape.FromMap
  alias Refract.Shape.Load
  alias Refract.Table.Spec

  import Refract.String.Utils, only: [blank?: 1]

  @type marker :: {:file, Regex.t()} | {:content, Regex.t()}

  @type t :: %__MODULE__{
          name: String.t(),
          version: pos_integer(),
          spec: Spec.t(),
          markers: [marker()]
        }

  defstruct [:name, :version, :spec, :markers]

  @type opt ::
          {:name, String.t()}
          | {:spec, Spec.t()}
          | {:version, pos_integer()}
          | {:markers, [marker()]}

  @type error ::
          {:not_a_map, term()}
          | {:missing_key, String.t()}
          | {:unknown_key, String.t()}
          | {:invalid_value, {String.t(), term()}}
          | {:invalid_spec, String.t()}

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
    opts = Keyword.validate!(opts, [:name, :spec, version: 1, markers: []])

    name = Keyword.get(opts, :name)
    spec = Keyword.get(opts, :spec)

    version = Keyword.get(opts, :version)
    markers = Keyword.get(opts, :markers)

    validate_name(name)
    validate_spec(spec)
    validate_version(version)
    validate_markers(markers)

    %__MODULE__{
      name: name,
      version: version,
      spec: spec,
      markers: markers
    }
  end

  @spec from_map(term()) :: {:ok, t()} | {:error, error()}

  def from_map(map), do: FromMap.run(map)

  @spec from_map!(term()) :: t()

  def from_map!(map) do
    case from_map(map) do
      {:ok, shape} ->
        shape

      {:error, reason} ->
        raise ArgumentError, "cannot create shape from map: #{describe_error(reason)}"
    end
  end

  @spec load(Path.t()) :: {:ok, t()} | {:error, load_error()}

  def load(path), do: Load.run(path)

  @spec load!(Path.t()) :: t()

  def load!(path) do
    case load(path) do
      {:ok, shape} ->
        shape

      {:error, reason} ->
        raise ArgumentError, "cannot load shape from #{path}: #{describe_error(reason)}"
    end
  end

  defp describe_error({:invalid_value, {key, _value}}), do: "invalid_value #{key}"

  defp describe_error({reason, detail}) when is_binary(detail), do: "#{reason} #{detail}"

  defp describe_error({reason, _detail}), do: "#{reason}"

  defp validate_name(name) when is_binary(name) do
    if blank?(name) do
      raise ArgumentError, "name must not be blank"
    end
  end

  defp validate_name(_), do: raise(ArgumentError, "name must be a string")

  defp validate_spec(%Spec{}), do: :ok

  defp validate_spec(_), do: raise(ArgumentError, "spec must be a Refract.Table.Spec")

  defp validate_version(version) when is_integer(version) and version > 0, do: :ok

  defp validate_version(_), do: raise(ArgumentError, "version must be a positive integer")

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
