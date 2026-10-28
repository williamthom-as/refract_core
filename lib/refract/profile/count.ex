defmodule Refract.Profile.Count do
  @moduledoc false

  alias Refract.Profile.Column
  alias Refract.Profile.Group
  alias Refract.Profile.Result
  alias Refract.Profile.Variant
  alias Refract.Shape
  alias Refract.Table.Locate
  alias Refract.Table.Report

  import Refract.String.Utils, only: [blank?: 1]

  defstruct blanks: 0, seen: 0, values: %{}, capped: false

  @type opt ::
          {:within, non_neg_integer()}
          | {:header_row, pos_integer() | nil}
          | {:except, [String.t()]}
          | {:max_distinct, pos_integer()}
          | {:max_lines, pos_integer()}

  @spec run(Enumerable.t(), Shape.t() | module(), [opt()]) ::
          {:ok, Result.t()} | {:error, {:header_not_found, Locate.header_miss()}}

  def run(raw, shape, opts) do
    {header_opts, opts} = Keyword.split(opts, [:within, :header_row])
    opts = Keyword.validate!(opts, except: [], max_distinct: 5000, max_lines: 100)
    except = Keyword.fetch!(opts, :except)
    max_distinct = Keyword.fetch!(opts, :max_distinct)
    max_lines = Keyword.fetch!(opts, :max_lines)

    %Shape{spec: spec} = Shape.resolve(shape)

    validate_except(except, spec.header.columns)
    validate_limit(max_distinct, :max_distinct)
    validate_limit(max_lines, :max_lines)

    with {:ok, _header_row, positions, steps} <-
           Locate.body(raw, spec, [{:misses, :unlimited} | header_opts]) do
      counts = positions |> Map.keys() |> Kernel.--(except) |> Map.new(&{&1, %__MODULE__{}})

      {rows, counts} =
        Enum.reduce(steps, {0, counts}, &add_row(&1, &2, {max_distinct, max_lines}))

      {:ok,
       %Result{
         rows: rows,
         columns: Map.new(counts, fn {name, count} -> {name, column(count)} end)
       }}
    end
  end

  defp add_row({_kind, row, %Report.Line{row: line}}, {rows, counts}, limits) do
    {rows + 1,
     Map.new(counts, fn {name, count} -> {name, add(count, Map.get(row, name), line, limits)} end)}
  end

  defp add(count, cell, line, limits), do: add(count, blank?(cell), cell, line, limits)

  defp add(%__MODULE__{blanks: blanks} = count, true, _cell, _line, _limits),
    do: %{count | blanks: blanks + 1}

  defp add(%__MODULE__{capped: true} = count, false, _cell, _line, _limits), do: count

  defp add(%__MODULE__{values: values} = count, false, cell, line, {_max_distinct, max_lines})
       when is_map_key(values, cell),
       do: %{count | values: Map.update!(values, cell, &seen_again(&1, line, max_lines))}

  defp add(%__MODULE__{values: values} = count, false, _cell, _line, {max_distinct, _max_lines})
       when map_size(values) >= max_distinct,
       do: %{count | capped: true, values: %{}}

  defp add(%__MODULE__{values: values, seen: seen} = count, false, cell, line, _limits) do
    variant = %Variant{value: cell, count: 1, lines: [line]}

    %{count | values: Map.put(values, cell, {seen, variant}), seen: seen + 1}
  end

  defp seen_again({order, %Variant{count: count, lines: lines} = variant}, line, max_lines)
       when count < max_lines,
       do: {order, %{variant | count: count + 1, lines: [line | lines]}}

  defp seen_again({order, %Variant{count: count} = variant}, _line, _max_lines),
    do: {order, %{variant | count: count + 1}}

  defp column(%__MODULE__{capped: true, blanks: blanks}),
    do: %Column{blanks: blanks, distinct: nil, capped: true}

  defp column(%__MODULE__{blanks: blanks, values: values}),
    do: %Column{blanks: blanks, distinct: map_size(values), clusters: Group.clusters(values)}

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
