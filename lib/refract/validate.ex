defmodule Refract.Validate do
  @moduledoc """
  validate a file against a set of rules applied to each row/column.

  can be per cell or across entire row
  """

  alias Refract.Shape
  alias Refract.Table.Body
  alias Refract.Table.Locate
  alias Refract.Table.Report

  alias Refract.Validate.Check
  alias Refract.Validate.Issue
  alias Refract.Validate.Result
  alias Refract.Validate.Rules

  import Refract.String.Utils, only: [blank?: 1]

  @type opt :: {:values, boolean()}

  @type tagged :: {:ok, Refract.row()} | {:invalid, Refract.row(), [Issue.t()]}

  @spec rows(Enumerable.t(), Shape.t() | module(), [opt()]) :: Enumerable.t(tagged())

  def rows(rows, shape, opts \\ []) do
    opts = Keyword.validate!(opts, values: false)
    values = Keyword.fetch!(opts, :values)

    %Shape{validation: %Rules{columns: columns, rows: row_rules}} = Shape.resolve(shape)
    columns = Enum.sort(columns)

    rows
    |> Stream.with_index(1)
    |> Stream.map(fn {row, line} ->
      mark_row(row, issues(row, line, columns, row_rules, values))
    end)
  end

  @spec source(Enumerable.t(), Shape.t() | module(), keyword()) ::
          {:ok, Result.t()} | {:error, {:header_not_found, Locate.header_miss()}}

  def source(raw, shape, opts) do
    {header_opts, opts} = Keyword.split(opts, [:within, :header_row])

    opts = Keyword.validate!(opts, values: false)
    values = Keyword.fetch!(opts, :values)

    %Shape{spec: spec, validation: %Rules{columns: columns, rows: row_rules}} =
      Shape.resolve(shape)

    with {:ok, header_row, positions} <- Locate.header(raw, spec, header_opts) do
      absent = Locate.absent(spec, positions)
      columns = Enum.sort(columns)

      steps =
        raw
        |> Stream.with_index(1)
        |> Stream.drop(header_row)
        |> Body.run(spec, positions, false, misses: :unlimited)
        |> Enum.to_list()

      issues = Enum.flat_map(steps, &step_issues(&1, absent, columns, row_rules, values))

      {:ok, %Result{valid: issues == [], rows: length(steps), issues: issues}}
    end
  end

  defp step_issues(
         {_kind, row, %Report.Line{row: line, columns: recognised}},
         absent,
         columns,
         row_rules,
         values
       ) do
    row = Map.merge(row, absent)
    validation = column_issues(row, line, columns, values)
    covered = Enum.map(validation, & &1.column)

    recognition =
      for {column, %Report.Column{passed: false, rule: rule}} <- recognised,
          column not in covered,
          do: %Issue{
            line: line,
            column: column,
            rule: {:recognition, rule},
            value: shown(values, Map.get(row, column))
          }

    Enum.sort_by(validation ++ recognition, & &1.column) ++ row_issues(row, line, row_rules)
  end

  defp mark_row(row, []), do: {:ok, row}
  defp mark_row(row, issues), do: {:invalid, row, issues}

  defp issues(row, line, columns, row_rules, values),
    do: column_issues(row, line, columns, values) ++ row_issues(row, line, row_rules)

  defp column_issues(row, line, columns, values) do
    for {column, rules} <- columns,
        cell = Map.get(row, column),
        rule = first_failed(rules, cell),
        rule != nil,
        do: %Issue{line: line, column: column, rule: rule_name(rule), value: shown(values, cell)}
  end

  defp row_issues(row, line, row_rules) do
    for {name, fun} <- row_rules,
        not Check.holds?(fun, row),
        do: %Issue{line: line, column: nil, rule: name}
  end

  defp first_failed(rules, cell), do: cell |> blank?() |> first_failed(rules, cell)

  defp first_failed(true, rules, _cell), do: if(:required in rules, do: :required)
  defp first_failed(false, rules, cell), do: Enum.find(rules, &(not Check.passes?(&1, cell)))

  defp rule_name({name, fun}) when is_atom(name) and is_function(fun, 1), do: name
  defp rule_name(rule), do: rule

  defp shown(true, cell), do: cell
  defp shown(false, _cell), do: nil
end
