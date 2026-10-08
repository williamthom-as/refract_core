defmodule Refract.Table.Spec.Header do
  @moduledoc false

  defstruct [:columns, :required, :min_matches]

  import Refract.String.Utils, only: [normalise: 1]

  alias Refract.Table.Report

  @type t :: %__MODULE__{
          columns: %{String.t() => [String.t() | Regex.t()]},
          required: [String.t()],
          min_matches: non_neg_integer()
        }

  def new(opts) do
    opts = Keyword.validate!(opts, [:columns, :min_matches, required: []])

    columns =
      case Keyword.fetch(opts, :columns) do
        :error ->
          raise ArgumentError, "header columns are required"

        {:ok, columns} when not is_map(columns) ->
          raise ArgumentError, "header columns must be a map"

        {:ok, columns} ->
          Map.new(columns, fn {key, patterns} ->
            {key, Enum.map(patterns, &normalise/1)}
          end)
      end

    required = Keyword.get(opts, :required)
    min_matches = Keyword.get(opts, :min_matches, map_size(columns))

    validate_columns(columns)
    validate_min_matches(columns, min_matches)

    validate_required(columns, required)

    %__MODULE__{
      columns: columns,
      required: required,
      min_matches: min_matches
    }
  end

  defp validate_columns(columns) when map_size(columns) == 0 do
    raise ArgumentError, "header needs at least one column"
  end

  defp validate_columns(columns) do
    Enum.each(columns, fn {column, patterns} ->
      if patterns == [] do
        raise ArgumentError, "header column #{column} has no aliases"
      end
    end)
  end

  defp validate_min_matches(columns, min_matches) do
    if min_matches > map_size(columns) do
      raise ArgumentError, "min_matches cannot be greater than the number of header columns"
    end
  end

  defp validate_required(columns, required) do
    Enum.each(required, fn req ->
      if not Map.has_key?(columns, req) do
        raise ArgumentError, "required column #{req} is not in header columns"
      end
    end)
  end

  @type positions :: %{String.t() => non_neg_integer()}

  @type miss :: %{matched: [String.t()], missing: [String.t()]}

  @type report :: Report.Line.t()

  @spec matches(t(), Refract.raw_row()) :: {:ok, positions()} | {:error, miss()}

  def matches(%__MODULE__{} = header, line) do
    report = report(header, line)
    positions = positions(report)

    if report.passed do
      {:ok, positions}
    else
      {:error, %{matched: Map.keys(positions), missing: required_missing(report)}}
    end
  end

  @spec positions(report()) :: positions()

  def positions(%Report.Line{columns: columns}) do
    for {column, %Report.Column{passed: true, index: index}} <- columns,
        into: %{},
        do: {column, index}
  end

  @spec required_missing(report()) :: [String.t()]

  def required_missing(%Report.Line{rules: rules}) do
    %Report.Rule{missing: missing} = Enum.find(rules, &(&1.rule == :required))

    missing
  end

  defp pattern_matches?(%Regex{} = pattern, col, _normalised_col), do: Regex.match?(pattern, col)

  defp pattern_matches?(pattern, _col, normalised_col), do: normalised_col == pattern

  @spec report(t(), Refract.raw_row()) :: report()

  def report(%__MODULE__{columns: columns} = header, line) do
    column_reports =
      Map.new(columns, fn {column, patterns} ->
        {column, column_report(line, patterns)}
      end)

    matched = for {column, %Report.Column{passed: true}} <- column_reports, do: column
    rules = [min_matches_rule(header, matched), required_rule(header, matched)]

    passed = Enum.all?(rules, & &1.passed)

    Report.Line.for_header(nil, passed, column_reports, rules)
  end

  defp column_report(line, patterns) do
    line
    |> Enum.with_index()
    |> Enum.find_value(%Report.Column{}, fn {cell, index} ->
      cell_report(cell, index, patterns)
    end)
  end

  defp cell_report(cell, index, patterns) when is_binary(cell) do
    normalised_cell = normalise(cell)

    case Enum.find(patterns, &pattern_matches?(&1, cell, normalised_cell)) do
      nil ->
        nil

      matched_pattern ->
        %Report.Column{passed: true, index: index, cell: cell, rule: matched_pattern}
    end
  end

  defp cell_report(_cell, _index, _patterns), do: nil

  defp min_matches_rule(%__MODULE__{min_matches: min_matches}, matched) do
    actual = length(matched)

    Report.Rule.for_min_matches(actual >= min_matches, min_matches, actual)
  end

  defp required_rule(%__MODULE__{required: required}, matched) do
    missing = Enum.reject(required, &(&1 in matched))

    Report.Rule.for_required(missing == [], required, missing)
  end
end
