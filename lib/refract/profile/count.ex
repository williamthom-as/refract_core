defmodule Refract.Profile.Count do
  @moduledoc false

  alias Refract.ArgValidator
  alias Refract.Profile.Column
  alias Refract.Profile.Ctx
  alias Refract.Profile.Group
  alias Refract.Profile.Result
  alias Refract.Profile.Variant
  alias Refract.Shape
  alias Refract.Table.Locate
  alias Refract.Table.Report
  alias Refract.Table.Spec

  import Refract.String.Utils, only: [blank?: 1]

  defstruct blanks: 0, seen: 0, values: %{}, capped: false

  @type location :: {Path.t() | nil, pos_integer()}

  @type t :: %__MODULE__{
          blanks: non_neg_integer(),
          seen: non_neg_integer(),
          values: %{Refract.cell() => {non_neg_integer(), pos_integer(), [location()]}},
          capped: boolean()
        }

  @type counted :: {non_neg_integer(), %{String.t() => t()}}

  @type opt ::
          {:within, non_neg_integer()}
          | {:header_row, pos_integer() | nil}
          | {:except, [String.t()]}
          | {:max_distinct, pos_integer()}
          | {:max_lines, pos_integer()}
          | {:values, boolean()}
          | {:fuzzy, number() | false}

  @spec run(Enumerable.t(), Shape.t() | module(), [opt()]) ::
          {:ok, Result.t()} | {:error, {:header_not_found, Locate.header_miss()}}

  def run(raw, shape, opts) do
    %Shape{spec: spec} = shape = Shape.resolve(shape)
    ctx = ctx!(opts, spec.header.columns)

    with {:ok, counted} <- add_file({0, %{}}, raw, nil, spec, ctx) do
      {rows, columns} = finish(counted, :lines, ctx)

      {:ok, %Result{shape: shape, rows: rows, columns: columns}}
    end
  end

  @spec options() :: keyword()

  def options do
    [
      except: [],
      max_distinct: 5000,
      max_lines: 100,
      values: false,
      fuzzy: 0.94,
      columns: :shape
    ]
  end

  @spec ctx!([opt()], %{String.t() => term()}) :: Ctx.t()

  def ctx!(opts, columns) do
    {header_opts, opts} = Keyword.split(opts, Keyword.keys(Locate.header_options()))

    opts = Keyword.validate!(opts, options())

    except = Keyword.fetch!(opts, :except)
    values = Keyword.fetch!(opts, :values)
    fuzzy = Keyword.fetch!(opts, :fuzzy)
    column_mode = Keyword.fetch!(opts, :columns)
    max_distinct = Keyword.fetch!(opts, :max_distinct)
    max_lines = Keyword.fetch!(opts, :max_lines)

    validate_columns(column_mode)
    validate_except(except, columns, column_mode)
    ArgValidator.validate_positive_integer!(max_distinct, :max_distinct)
    ArgValidator.validate_positive_integer!(max_lines, :max_lines)
    ArgValidator.validate_boolean!(values, :values)
    validate_fuzzy!(fuzzy)

    %Ctx{
      except: except,
      values: values,
      fuzzy: fuzzy,
      columns: column_mode,
      max_distinct: max_distinct,
      max_lines: max_lines,
      header_opts: header_opts
    }
  end

  @spec add_file(counted(), Enumerable.t(), Path.t() | nil, Spec.t(), Ctx.t()) ::
          {:ok, counted()} | {:error, {:header_not_found, Locate.header_miss()}}

  def add_file({rows, counts}, raw, path, spec, %Ctx{except: except} = ctx) do
    with {:ok, _header_row, positions, steps} <-
           Locate.body(raw, spec, [misses: :unlimited, columns: ctx.columns] ++ ctx.header_opts) do
      present = Map.keys(positions) -- except

      counts =
        Enum.reduce(present, counts, &Map.put_new(&2, &1, %__MODULE__{}))

      {:ok, Enum.reduce(steps, {rows, counts}, &add_row(&1, &2, present, path, ctx))}
    end
  end

  @spec finish(counted(), :lines | :files, Ctx.t()) ::
          {non_neg_integer(), %{String.t() => Column.t()}}

  def finish({rows, counts}, place, %Ctx{} = ctx),
    do: {rows, Map.new(counts, fn {name, count} -> {name, column(count, place, ctx)} end)}

  defp add_row({_kind, row, %Report.Line{row: line}}, {rows, counts}, present, path, ctx) do
    {rows + 1,
     Enum.reduce(present, counts, fn name, counts ->
       Map.update!(counts, name, &add(&1, Map.get(row, name), {path, line}, ctx))
     end)}
  end

  defp add(count, cell, location, ctx), do: add(count, blank?(cell), cell, location, ctx)

  defp add(%__MODULE__{blanks: blanks} = count, true, _cell, _location, _ctx),
    do: %{count | blanks: blanks + 1}

  defp add(%__MODULE__{capped: true} = count, false, _cell, _location, _ctx), do: count

  defp add(%__MODULE__{values: values} = count, false, cell, location, %Ctx{max_lines: max_lines})
       when is_map_key(values, cell),
       do: %{count | values: Map.update!(values, cell, &seen_again(&1, location, max_lines))}

  defp add(%__MODULE__{values: values} = count, false, _cell, _location, %Ctx{
         max_distinct: max_distinct
       })
       when map_size(values) >= max_distinct,
       do: %{count | capped: true, values: %{}}

  defp add(%__MODULE__{values: values, seen: seen} = count, false, cell, location, _ctx),
    do: %{count | values: Map.put(values, cell, {seen, 1, [location]}), seen: seen + 1}

  defp seen_again({order, count, locations}, location, max_lines) when count < max_lines,
    do: {order, count + 1, [location | locations]}

  defp seen_again({order, count, locations}, _location, _max_lines),
    do: {order, count + 1, locations}

  defp column(%__MODULE__{capped: true, blanks: blanks}, _place, _ctx),
    do: %Column{blanks: blanks, distinct: nil, capped: true}

  defp column(%__MODULE__{blanks: blanks, values: values}, place, %Ctx{} = ctx) do
    variants =
      Map.new(values, fn {cell, {order, count, locations}} ->
        {cell, {order, variant(cell, count, Enum.reverse(locations), place)}}
      end)

    {fuzzy, clusters} = Group.clusters(variants, ctx.fuzzy)

    %Column{
      blanks: blanks,
      distinct: map_size(values),
      fuzzy: fuzzy,
      clusters: clusters,
      values: listed(variants, ctx.values)
    }
  end

  defp listed(_variants, false), do: nil

  defp listed(variants, true) do
    variants
    |> Map.values()
    |> Enum.sort_by(fn {order, %Variant{count: count}} -> {-count, order} end)
    |> Enum.map(fn {_order, variant} -> variant end)
  end

  defp variant(cell, count, locations, :lines),
    do: %Variant{
      value: cell,
      count: count,
      lines: Enum.map(locations, fn {_path, line} -> line end)
    }

  defp variant(cell, count, locations, :files) do
    %Variant{
      value: cell,
      count: count,
      files: Enum.group_by(locations, fn {path, _line} -> path end, fn {_path, line} -> line end)
    }
  end

  @spec validate_fuzzy!(term()) :: :ok

  def validate_fuzzy!(false), do: :ok
  def validate_fuzzy!(fuzzy) when is_number(fuzzy) and fuzzy >= 0 and fuzzy <= 1, do: :ok

  def validate_fuzzy!(fuzzy) do
    raise ArgumentError, "fuzzy must be a number from 0 to 1 or false, got: #{inspect(fuzzy)}"
  end

  defp validate_columns(columns) when columns in [:shape, :all], do: :ok

  defp validate_columns(columns) do
    raise ArgumentError, "columns must be :shape or :all, got: #{inspect(columns)}"
  end

  defp validate_except(except, columns, :shape) when is_list(except),
    do: except |> Enum.reject(&is_map_key(columns, &1)) |> validate_known()

  defp validate_except(except, _columns, :all) when is_list(except),
    do: except |> Enum.reject(&is_binary/1) |> validate_names()

  defp validate_except(except, _columns, _mode) do
    raise ArgumentError, "except must be a list of shape columns, got: #{inspect(except)}"
  end

  defp validate_names([]), do: :ok

  defp validate_names(bad) do
    raise ArgumentError, "except must be a list of column names, got: #{inspect(bad)}"
  end

  defp validate_known([]), do: :ok

  defp validate_known(unknown) do
    raise ArgumentError, "except must name shape columns, got: #{inspect(unknown)}"
  end
end
