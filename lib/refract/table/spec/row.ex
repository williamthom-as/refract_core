defmodule Refract.Table.Spec.Row do
  @moduledoc false

  import Refract.Utils, only: [truthy?: 1]

  alias Refract.Parse
  alias Refract.Table.Report

  defstruct [:match, :min_score]

  @type rule ::
          :integer
          | :number
          | :date
          | :datetime
          | Regex.t()
          | (Refract.cell() -> as_boolean(term()))

  @type rules :: %{String.t() => rule()}

  @type t :: %__MODULE__{
          match: rules(),
          min_score: number()
        }

  def new(opts) do
    opts = Keyword.validate!(opts, [:match, :min_score])

    match = Keyword.get(opts, :match, %{})
    min_score = Keyword.get(opts, :min_score, 1.0)

    validate_min_score(min_score)
    validate_rules(match)

    %__MODULE__{
      match: match,
      min_score: min_score
    }
  end

  defp validate_rules(rules) when is_map(rules) do
    Enum.each(rules, fn {column, rule} ->
      if not is_binary(column) do
        raise ArgumentError, "column names must be strings"
      end

      if not valid_rule?(rule) do
        raise ArgumentError, "invalid rule for column #{column}: #{inspect(rule)}"
      end
    end)
  end

  defp validate_rules(_), do: raise(ArgumentError, "match rules must be a map")

  defp valid_rule?(rule) when rule in [:integer, :number, :date, :datetime], do: true
  defp valid_rule?(%Regex{}), do: true
  defp valid_rule?(fun) when is_function(fun, 1), do: true
  defp valid_rule?(_), do: false

  defp validate_min_score(min_score)
       when is_number(min_score) and min_score >= 0 and min_score <= 1,
       do: :ok

  defp validate_min_score(_),
    do: raise(ArgumentError, "min_score must be a number between 0 and 1")

  @type miss :: %{score: float(), failed: [{String.t(), rule()}]}

  @spec matches(t(), Refract.row()) :: :ok | {:error, miss()}

  def matches(%__MODULE__{} = row_spec, row) do
    report = report(row_spec, row)

    if report.passed do
      :ok
    else
      [%Report.Rule{actual: score}] = report.rules

      {:error, %{score: score, failed: failed(report)}}
    end
  end

  defp failed(%Report.Line{columns: columns}) do
    for {column, %Report.Column{passed: false, rule: rule}} <- columns, do: {column, rule}
  end

  defp passes?(_, nil), do: false

  defp passes?(:integer, value), do: match?({:ok, _}, Parse.integer(value))

  defp passes?(:number, value), do: match?({:ok, _}, Parse.number(value))

  defp passes?(:date, value), do: match?({:ok, _}, Parse.date(value))

  defp passes?(:datetime, value), do: match?({:ok, _}, Parse.datetime(value, offset: :utc))

  defp passes?(%Regex{} = regex, value) when is_binary(value) do
    Regex.match?(regex, value)
  end

  defp passes?(fun, value) when is_function(fun, 1) do
    truthy?(fun.(value))
  end

  defp passes?(_, _), do: false

  @type report_opt :: {:values, boolean()}

  @type report :: Report.Line.t()

  @spec report(t(), Refract.row(), [report_opt()]) :: report()

  def report(row_spec, row, opts \\ [])

  def report(%__MODULE__{match: rules}, _row, opts) when map_size(rules) == 0 do
    opts = Keyword.validate!(opts, values: false)

    validate_values(Keyword.fetch!(opts, :values))

    Report.Line.for_row(nil, true, %{}, [])
  end

  def report(%__MODULE__{match: rules} = row_spec, row, opts) do
    opts = Keyword.validate!(opts, values: false)

    values = Keyword.fetch!(opts, :values)

    validate_values(values)

    column_reports =
      Map.new(rules, fn {column, rule} ->
        {column, column_report(row, column, rule, values)}
      end)

    rules = [min_score_rule(row_spec, column_reports)]

    Report.Line.for_row(nil, Enum.all?(rules, & &1.passed), column_reports, rules)
  end

  defp column_report(row, column, rule, values) do
    value = Map.get(row, column)

    %Report.Column{
      passed: passes?(rule, value),
      rule: rule,
      cell: cell(value, values)
    }
  end

  defp validate_values(values) when is_boolean(values), do: :ok

  defp validate_values(values) do
    raise ArgumentError, "values must be true or false, got: #{inspect(values)}"
  end

  defp cell(value, true), do: value

  defp cell(_value, false), do: nil

  defp min_score_rule(%__MODULE__{min_score: min_score}, column_reports) do
    passed = Enum.count(column_reports, fn {_column, column} -> column.passed end)
    score = passed / map_size(column_reports)

    Report.Rule.for_min_score(score >= min_score, min_score, score)
  end
end
