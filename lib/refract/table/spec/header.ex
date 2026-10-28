defmodule Refract.Table.Spec.Header do
  @moduledoc false

  defstruct [:columns, :required, :min_matches, :lookup, :regexes, ignore: []]

  import Refract.String.Utils, only: [blank?: 1, header_cell: 1, normalise: 1]

  alias Refract.Table.Report

  @type t :: %__MODULE__{
          columns: %{String.t() => [String.t() | Regex.t()]},
          required: [String.t()],
          min_matches: non_neg_integer(),
          lookup: %{String.t() => [{String.t(), rank()}]},
          regexes: %{String.t() => [{Regex.t(), rank()}]},
          ignore: [String.t() | Regex.t()]
        }

  @type rank :: {0 | 1, non_neg_integer()}

  @spec new(keyword()) :: t()

  def new(opts) do
    opts = Keyword.validate!(opts, [:columns, :min_matches, required: [], ignore: []])

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

    required = Keyword.fetch!(opts, :required)
    min_matches = Keyword.get(opts, :min_matches, map_size(columns))
    ignore = Keyword.fetch!(opts, :ignore)

    validate_columns(columns)
    validate_min_matches(columns, min_matches)
    validate_ignore(ignore)

    validate_required(columns, required)

    %__MODULE__{
      columns: columns,
      required: required,
      min_matches: min_matches,
      lookup: lookup(columns),
      regexes: regexes(columns),
      ignore: Enum.map(ignore, &normalise/1)
    }
  end

  defp lookup(columns) do
    for {column, patterns} <- columns,
        {pattern, rank} <- plain_aliases(column, patterns),
        reduce: %{} do
      acc -> Map.update(acc, pattern, [{column, rank}], &[{column, rank} | &1])
    end
  end

  defp plain_aliases(column, patterns) do
    patterns
    |> Enum.with_index(1)
    |> Enum.concat([{normalise(column), 0}])
    |> Enum.filter(fn {pattern, _position} -> is_binary(pattern) end)
    |> Enum.uniq_by(fn {pattern, _position} -> pattern end)
    |> Enum.map(fn {pattern, position} -> {pattern, {0, position}} end)
  end

  defp regexes(columns) do
    for {column, patterns} <- columns,
        regexes = ranked_regexes(patterns),
        regexes != [],
        into: %{},
        do: {column, regexes}
  end

  defp ranked_regexes(patterns) do
    patterns
    |> Enum.with_index(1)
    |> Enum.filter(fn {pattern, _position} -> is_struct(pattern, Regex) end)
    |> Enum.map(fn {regex, position} -> {regex, {1, position}} end)
  end

  defp validate_columns(columns) when map_size(columns) == 0 do
    raise ArgumentError, "header needs at least one column"
  end

  defp validate_columns(columns) do
    Enum.each(columns, fn {column, patterns} ->
      validate_column_name(column)
      validate_aliases(column, patterns)
    end)
  end

  defp validate_column_name(column) when is_binary(column), do: :ok

  defp validate_column_name(column) do
    raise ArgumentError, "header column name must be a string, got: #{inspect(column)}"
  end

  defp validate_aliases(_column, [_ | _]), do: :ok

  defp validate_aliases(column, []) do
    raise ArgumentError, "header column #{column} has no aliases"
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

  defp validate_ignore(ignore) when is_list(ignore), do: Enum.each(ignore, &validate_ignored/1)

  defp validate_ignore(ignore) do
    raise ArgumentError,
          "header ignore must be a list of names and regexes, got: #{inspect(ignore)}"
  end

  defp validate_ignored(name) when is_binary(name) or is_struct(name, Regex), do: :ok

  defp validate_ignored(name) do
    raise ArgumentError, "header ignore must be a string or regex, got: #{inspect(name)}"
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

  @spec matched_count(report()) :: non_neg_integer()

  def matched_count(report), do: map_size(positions(report))

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
    plain = group_hits(plain_hits(header, line, normalised_line))
    found = Map.merge(group_hits(regex_hits(header, line, Map.keys(plain))), plain)

    column_reports =
      Map.new(columns, fn {column, _patterns} ->
        {column, Map.get(found, column, %Report.Column{})}
      end)

    rules = rules(header, Map.keys(found))

    passed = Enum.all?(rules, & &1.passed)

    %Report.Line{
      check: :header,
      passed: passed,
      columns: column_reports,
      rules: rules,
      extra: extra(header, line, found)
    }
  end

  @spec extra(t(), Refract.raw_row(), %{String.t() => Report.Column.t()}) ::
          [{non_neg_integer(), Refract.cell()}]

  def extra(%__MODULE__{ignore: ignore}, line, found) do
    taken =
      for {_column, %Report.Column{index: index, others: others}} <- found,
          taken <- [index | Enum.map(others, &elem(&1, 0))],
          into: %{},
          do: {taken, true}

    for {cell, index} <- Enum.with_index(line),
        is_binary(cell),
        not blank?(cell),
        not is_map_key(taken, index),
        not ignored?(ignore, cell),
        do: {index, cell}
  end

  defp ignored?(ignore, cell), do: Enum.any?(ignore, &ignores?(&1, cell))

  defp ignores?(%Regex{} = regex, cell), do: Regex.match?(regex, header_cell(cell))

  defp ignores?(name, cell), do: normalise_cell(cell) == name

  @spec rules(t(), [String.t()]) :: [Report.Rule.t()]

  def rules(%__MODULE__{} = header, matched),
    do: [min_matches_rule(header, matched), required_rule(header, matched)]

  defp normalise_cell(cell) when is_binary(cell), do: cell |> header_cell() |> normalise()
  defp normalise_cell(_cell), do: nil

  defp plain_hits(%__MODULE__{lookup: lookup}, line, normalised_line) do
    for {{cell, normalised}, index} <- line |> Enum.zip(normalised_line) |> Enum.with_index(),
        {column, rank} <- Map.get(lookup, normalised, []),
        do: {column, {rank, index}, cell, normalised}
  end

  defp regex_hits(%__MODULE__{regexes: regexes}, line, found) do
    unfound = Map.drop(regexes, found)

    for {cell, index} <- Enum.with_index(line),
        cleaned = regex_text(cell),
        cleaned != nil,
        {column, column_regexes} <- unfound,
        {regex, rank} <- column_regexes,
        Regex.match?(regex, cleaned),
        do: {column, {rank, index}, cell, regex}
  end

  defp regex_text(cell) when is_binary(cell), do: header_cell(cell)
  defp regex_text(_cell), do: nil

  defp group_hits(hits) do
    hits
    |> Enum.group_by(fn {column, _position, _cell, _rule} -> column end)
    |> Map.new(fn {column, column_hits} -> {column, column_report(column_hits)} end)
  end

  defp column_report(hits) do
    [{_column, {_rank, index}, cell, rule} | _rest] =
      sorted = Enum.sort_by(hits, fn {_column, position, _cell, _rule} -> position end)

    others =
      sorted
      |> Enum.map(fn {_column, {_rank, other}, other_cell, _rule} -> {other, other_cell} end)
      |> Enum.reject(fn {other, _cell} -> other == index end)
      |> Enum.uniq_by(fn {other, _cell} -> other end)
      |> Enum.sort()

    %Report.Column{passed: true, index: index, cell: cell, rule: rule, others: others}
  end

  defp min_matches_rule(%__MODULE__{min_matches: min_matches}, matched) do
    actual = length(matched)

    Report.Rule.for_min_matches(actual >= min_matches, min_matches, actual)
  end

  defp required_rule(%__MODULE__{required: required}, matched) do
    missing = Enum.reject(required, &(&1 in matched))

    Report.Rule.for_required(missing == [], required, missing)
  end
end
