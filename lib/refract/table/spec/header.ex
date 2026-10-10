defmodule Refract.Table.Spec.Header do
  @moduledoc false

  defstruct [:columns, :required, :min_matches, :lookup, :regexes]

  import Refract.String.Utils, only: [normalise: 1]

  alias Refract.Table.Report

  @type t :: %__MODULE__{
          columns: %{String.t() => [String.t() | Regex.t()]},
          required: [String.t()],
          min_matches: non_neg_integer(),
          lookup: %{String.t() => [String.t()]},
          regexes: %{String.t() => [Regex.t()]}
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
      min_matches: min_matches,
      lookup: lookup(columns),
      regexes: regexes(columns)
    }
  end

  defp lookup(columns) do
    for {column, patterns} <- columns, pattern when is_binary(pattern) <- patterns, reduce: %{} do
      acc -> Map.update(acc, pattern, [column], &[column | &1])
    end
  end

  defp regexes(columns) do
    for {column, patterns} <- columns,
        regexes = Enum.filter(patterns, &is_struct(&1, Regex)),
        regexes != [],
        into: %{},
        do: {column, regexes}
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

  @spec normalise_line(Refract.raw_row()) :: [String.t() | nil]

  def normalise_line(line), do: Enum.map(line, &normalise_cell/1)

  @spec report(t(), Refract.raw_row()) :: report()

  def report(%__MODULE__{} = header, line), do: report(header, line, normalise_line(line))

  @spec report(t(), Refract.raw_row(), [String.t() | nil]) :: report()

  def report(%__MODULE__{columns: columns} = header, line, normalised_line) do
    found =
      header
      |> plain_matches(line, normalised_line)
      |> regex_matches(header, line)

    column_reports =
      Map.new(columns, fn {column, _patterns} ->
        {column, Map.get(found, column, %Report.Column{})}
      end)

    matched = Map.keys(found)
    rules = [min_matches_rule(header, matched), required_rule(header, matched)]

    passed = Enum.all?(rules, & &1.passed)

    %Report.Line{check: :header, passed: passed, columns: column_reports, rules: rules}
  end

  defp normalise_cell(cell) when is_binary(cell), do: normalise(cell)
  defp normalise_cell(_cell), do: nil

  defp plain_matches(%__MODULE__{lookup: lookup}, line, normalised_line) do
    line
    |> Enum.zip(normalised_line)
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {{cell, normalised}, index}, found ->
      lookup
      |> Map.get(normalised, [])
      |> Enum.reduce(found, fn column, acc ->
        Map.put_new(acc, column, %Report.Column{
          passed: true,
          index: index,
          cell: cell,
          rule: normalised
        })
      end)
    end)
  end

  defp regex_matches(found, %__MODULE__{regexes: regexes}, line) do
    regexes
    |> Map.drop(Map.keys(found))
    |> Enum.reduce(found, fn {column, column_regexes}, acc ->
      case regex_column(line, column_regexes) do
        nil -> acc
        column_report -> Map.put(acc, column, column_report)
      end
    end)
  end

  defp regex_column(line, regexes) do
    line
    |> Enum.with_index()
    |> Enum.find_value(fn {cell, index} -> regex_cell(cell, index, regexes) end)
  end

  defp regex_cell(cell, index, regexes) when is_binary(cell) do
    case Enum.find(regexes, &Regex.match?(&1, cell)) do
      nil -> nil
      regex -> %Report.Column{passed: true, index: index, cell: cell, rule: regex}
    end
  end

  defp regex_cell(_cell, _index, _regexes), do: nil

  defp min_matches_rule(%__MODULE__{min_matches: min_matches}, matched) do
    actual = length(matched)

    Report.Rule.for_min_matches(actual >= min_matches, min_matches, actual)
  end

  defp required_rule(%__MODULE__{required: required}, matched) do
    missing = Enum.reject(required, &(&1 in matched))

    Report.Rule.for_required(missing == [], required, missing)
  end
end
