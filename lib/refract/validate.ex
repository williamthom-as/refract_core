defmodule Refract.Validate do
  @moduledoc """
  validate a files content against its shapes `validation:` and `fields:` ruleset.

  - column rules per cell and row rules across a row, issues by line (raw file line num from
    `source/3`, the rows position from 1 in `rows/3`)
  - field rules on the values read around the table (can be found anywhere)
  - document rules over the field values and every table row together
  """

  alias Refract.Shape
  alias Refract.Shape.Field
  alias Refract.Table.Locate
  alias Refract.Table.Report

  alias Refract.Validate.Check
  alias Refract.Validate.Issue
  alias Refract.Validate.Result
  alias Refract.Validate.Rules

  import Refract.String.Utils, only: [blank?: 1]

  @type opt :: {:values, boolean()} | {:identify_by, String.t() | [String.t()] | nil}

  @type tagged :: {:ok, Refract.row()} | {:invalid, Refract.row(), [Issue.t()]}

  @doc "the options validate takes besides the header search with defaults"
  @spec options() :: keyword()

  def options, do: [values: false, indexing: :lines, identify_by: nil]

  @spec rows(Enumerable.t(), Shape.t() | module(), [opt()]) :: Enumerable.t(tagged())

  def rows(rows, shape, opts \\ []) do
    opts = Keyword.validate!(opts, Keyword.take(options(), [:values, :identify_by]))
    values = Keyword.fetch!(opts, :values)
    identify_by = opts |> Keyword.fetch!(:identify_by) |> identify_by()

    %Shape{validation: %Rules{columns: columns, rows: row_rules}} = Shape.resolve(shape)
    columns = Enum.sort(columns)

    rows
    |> Stream.with_index(1)
    |> Stream.map(fn {row, line} ->
      issues = row |> issues(line, columns, row_rules, values) |> recorded(row, identify_by)

      mark_row(row, issues)
    end)
  end

  @spec source(Enumerable.t(), Shape.t() | module(), keyword()) ::
          {:ok, Result.t()} | {:error, {:header_not_found, Locate.header_miss()}}

  def source(raw, shape, opts) do
    with {:ok, missing, steps} <- steps(raw, shape, opts) do
      {count, issues} =
        Enum.reduce(steps, {0, Enum.reverse(missing)}, fn {_row, issues}, {count, found} ->
          {count + 1, Enum.reverse(issues, found)}
        end)

      {:ok, result(count, Enum.reverse(issues))}
    end
  end

  @doc false
  @spec table(Enumerable.t(), Shape.t() | module(), keyword()) ::
          {:ok, Result.t(), [Refract.row()]} | {:error, {:header_not_found, Locate.header_miss()}}

  def table(raw, shape, opts) do
    with {:ok, missing, steps} <- steps(raw, shape, opts) do
      {rows, issues} = Enum.unzip(steps)

      {:ok, result(length(rows), missing ++ List.flatten(issues)), rows}
    end
  end

  defp steps(raw, shape, opts) do
    {header_opts, opts} = Keyword.split(opts, Keyword.keys(Locate.header_options()))

    opts = Keyword.validate!(opts, options())
    values = Keyword.fetch!(opts, :values)
    indexing = Keyword.fetch!(opts, :indexing)
    identify_by = opts |> Keyword.fetch!(:identify_by) |> identify_by()

    %Shape{spec: spec, validation: %Rules{columns: columns, rows: row_rules}} =
      Shape.resolve(shape)

    with {:ok, header_row, positions, steps} <-
           Locate.body(raw, spec, [misses: :unlimited, indexing: indexing] ++ header_opts) do
      absent = Locate.absent(spec, positions)
      {missing, columns} = columns |> Enum.sort() |> Enum.split_with(&missing?(&1, absent))

      {:ok, Enum.map(missing, &missing_issue(&1, header_row)),
       Stream.map(steps, fn {kind, row, report} ->
         row = Map.merge(row, absent)

         {row,
          {kind, row, report}
          |> step_issues(columns, row_rules, values)
          |> recorded(row, identify_by)}
       end)}
    end
  end

  defp missing?({column, rules}, absent), do: is_map_key(absent, column) and :required in rules

  defp missing_issue({column, _rules}, header_row),
    do: %Issue{line: header_row, column: column, rule: :column_missing}

  defp result(count, issues), do: with_issues(%Result{rows: count}, issues)

  defp with_issues(result, issues), do: %{result | issues: issues, valid: issues == []}

  @spec document(Result.t(), [Refract.row()], Shape.t() | module()) :: Result.t()

  def document(%Result{issues: issues, fields: fields} = result, rows, shape) do
    %Shape{validation: %Rules{document: rules}} = Shape.resolve(shape)

    document = %{fields: fields, rows: rows}

    issues =
      issues ++ for {name, fun} <- rules, not Check.holds?(fun, document), do: %Issue{rule: name}

    with_issues(result, issues)
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
          do: %Issue{line: line, field: name, rule: rule_name(rule), value: shown(values, cell)}

    %{
      with_issues(result, field_issues ++ issues)
      | fields: Map.new(located, fn {name, {cell, _line}} -> {name, cell} end)
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
            rule: {:recognition, rule_name(rule)},
            value: shown(values, Map.get(row, column))
          }

    Enum.sort_by(validation ++ recognition, & &1.column) ++ row_issues(row, line, row_rules)
  end

  defp identify_by(nil), do: nil
  defp identify_by(column) when is_binary(column), do: [column]

  defp identify_by([_ | _] = columns) do
    if Enum.all?(columns, &is_binary/1), do: columns, else: invalid_identify_by(columns)
  end

  defp identify_by(identify_by), do: invalid_identify_by(identify_by)

  defp invalid_identify_by(identify_by) do
    raise ArgumentError,
          "identify_by must be a column name or a list of them, got: #{inspect(identify_by)}"
  end

  defp recorded(issues, _row, nil), do: issues

  defp recorded(issues, row, identify_by) do
    record = Map.new(identify_by, &{&1, Map.get(row, &1)})

    Enum.map(issues, &%{&1 | record: record})
  end

  defp mark_row(row, []), do: {:ok, row}
  defp mark_row(row, issues), do: {:invalid, row, issues}

  defp issues(row, line, columns, row_rules, values),
    do: column_issues(row, line, columns, values) ++ row_issues(row, line, row_rules)

  defp column_issues(row, line, columns, values) do
    for {column, rules} <- columns,
        cell <- [Map.get(row, column)],
        rule = first_failed(rules, cell),
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
