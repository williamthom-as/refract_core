defmodule Refract.Profile.Count do
  @moduledoc false

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

  @spec run(Enumerable.t(), Shape.t() | module(), [opt()]) ::
          {:ok, Result.t()} | {:error, {:header_not_found, Locate.header_miss()}}

  def run(raw, shape, opts) do
    %Shape{spec: spec} = shape = Shape.resolve(shape)
    ctx = ctx!(opts, spec.header.columns)

    with {:ok, counted} <- add_file({0, %{}}, raw, nil, spec, ctx) do
      {rows, columns} = finish(counted, :lines)

      {:ok, %Result{shape: shape, rows: rows, columns: columns}}
    end
  end

  @spec ctx!([opt()], %{String.t() => term()}) :: Ctx.t()

  def ctx!(opts, columns) do
    {header_opts, opts} = Keyword.split(opts, [:within, :header_row])
    opts = Keyword.validate!(opts, except: [], max_distinct: 5000, max_lines: 100)
    except = Keyword.fetch!(opts, :except)
    max_distinct = Keyword.fetch!(opts, :max_distinct)
    max_lines = Keyword.fetch!(opts, :max_lines)

    validate_except(except, columns)
    validate_limit(max_distinct, :max_distinct)
    validate_limit(max_lines, :max_lines)

    %Ctx{
      except: except,
      max_distinct: max_distinct,
      max_lines: max_lines,
      header_opts: header_opts
    }
  end

  @spec add_file(counted(), Enumerable.t(), Path.t() | nil, Spec.t(), Ctx.t()) ::
          {:ok, counted()} | {:error, {:header_not_found, Locate.header_miss()}}

  def add_file({rows, counts}, raw, path, spec, %Ctx{except: except} = ctx) do
    with {:ok, _header_row, positions, steps} <-
           Locate.body(raw, spec, [{:misses, :unlimited} | ctx.header_opts]) do
      present = Map.keys(positions) -- except
      counts = Enum.reduce(present, counts, &Map.put_new(&2, &1, %__MODULE__{}))

      {:ok, Enum.reduce(steps, {rows, counts}, &add_row(&1, &2, present, path, ctx))}
    end
  end

  @spec finish(counted(), :lines | :files) :: {non_neg_integer(), %{String.t() => Column.t()}}

  def finish({rows, counts}, place),
    do: {rows, Map.new(counts, fn {name, count} -> {name, column(count, place)} end)}

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

  defp column(%__MODULE__{capped: true, blanks: blanks}, _place),
    do: %Column{blanks: blanks, distinct: nil, capped: true}

  defp column(%__MODULE__{blanks: blanks, values: values}, place) do
    {fuzzy, clusters} =
      values
      |> Map.new(fn {cell, {order, count, locations}} ->
        {cell, {order, variant(cell, count, Enum.reverse(locations), place)}}
      end)
      |> Group.clusters()

    %Column{blanks: blanks, distinct: map_size(values), fuzzy: fuzzy, clusters: clusters}
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

  defp validate_except(except, columns) when is_list(except),
    do: except |> Enum.reject(&is_map_key(columns, &1)) |> validate_known()

  defp validate_except(except, _columns) do
    raise ArgumentError, "except must be a list of shape columns, got: #{inspect(except)}"
  end

  defp validate_known([]), do: :ok

  defp validate_known(unknown) do
    raise ArgumentError, "except must name shape columns, got: #{inspect(unknown)}"
  end

  defp validate_limit(limit, _name) when is_integer(limit) and limit > 0, do: :ok

  defp validate_limit(limit, name) do
    raise ArgumentError, "#{name} must be a positive integer, got: #{inspect(limit)}"
  end
end
