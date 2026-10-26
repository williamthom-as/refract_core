defmodule Refract.Validate do
  @moduledoc """
  validate a files content against its shapes `validation:` and `fields:` ruleset.

  - column rules per cell and row rules across a row, issues by line (raw file line num)
  - field rules on the values read around the table (can be found anywhere)
  - document rules over the field values and every table row together
  """

  alias Refract.Shape
  alias Refract.Shape.Field
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
    with {:ok, result, _rows} <- table(raw, shape, opts), do: {:ok, result}
  end

  @doc false
  @spec table(Enumerable.t(), Shape.t() | module(), keyword()) ::
          {:ok, Result.t(), [Refract.row()]} | {:error, {:header_not_found, Locate.header_miss()}}

  def table(raw, shape, opts) do
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
        |> Enum.map(fn {kind, row, report} -> {kind, Map.merge(row, absent), report} end)

      issues = Enum.flat_map(steps, &step_issues(&1, columns, row_rules, values))
      rows = Enum.map(steps, fn {_kind, row, _report} -> row end)

      {:ok, %Result{valid: issues == [], rows: length(steps), issues: issues}, rows}
    end
  end

  @spec document(Result.t(), [Refract.row()], Shape.t() | module()) :: Result.t()

  def document(%Result{issues: issues, fields: fields} = result, rows, shape) do
    %Shape{validation: %Rules{document: rules}} = Shape.resolve(shape)

    document = %{fields: fields, rows: rows}

    issues =
      issues ++ for {name, fun} <- rules, not Check.holds?(fun, document), do: %Issue{rule: name}

    %{result | issues: issues, valid: issues == []}
  end

  @spec fields(
          Result.t(),
          %{String.t() => {Refract.cell(), pos_integer() | nil}},
          Shape.t() | module(),
          keyword()
        ) :: Result.t()

  def fields(%Result{issues: issues} = result, located, shape, opts) do
    %Shape{fields: fields} = Shape.resolve(shape)
    values = Keyword.get(opts, :values, false)

    field_issues =
      for {name, %Field{rules: rules}} <- Enum.sort(fields),
          {cell, line} = Map.fetch!(located, name),
          rule = first_failed(rules, cell),
          rule != nil,
          do: %Issue{line: line, field: name, rule: rule_name(rule), value: shown(values, cell)}

    issues = field_issues ++ issues

    %{
      result
      | fields: Map.new(located, fn {name, {cell, _line}} -> {name, cell} end),
        issues: issues,
        valid: issues == []
    }
  end

  defp step_issues(
         {_kind, row, %Report.Line{row: line, columns: recognised}},
         columns,
         row_rules,
         values
       ) do
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
