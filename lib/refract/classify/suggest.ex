defmodule Refract.Classify.Suggest do
  @moduledoc false

  alias Refract.Shape

  alias Refract.Table.Report.Column
  alias Refract.Table.Report.Line

  alias Refract.Table.Spec.Header
  alias Refract.Table.Spec.Row

  import Refract.String.Utils, only: [blank?: 1, blank_line?: 1, normalise: 1]

  @type opt :: {:within, pos_integer()} | {:header_row, pos_integer() | nil}

  @spec run(Enumerable.t(), Shape.t() | module(), [opt()]) :: Line.t()

  def run(raw, shape, opts) do
    opts = Keyword.validate!(opts, within: 100, header_row: nil)
    within = Keyword.fetch!(opts, :within)
    header_row = Keyword.fetch!(opts, :header_row)

    validate_within(within)
    validate_header_row(header_row)

    resolved_shape = Shape.resolve(shape)
    header = resolved_shape.spec.header
    rules = resolved_shape.spec.row.match

    sample = sample(raw, within, header_row)

    sample
    |> candidate_lines(header_row)
    |> Enum.map(fn {line, row_num} ->
      {row_num, line, assign(line, header, rules, rows_below(sample, row_num))}
    end)
    |> Enum.max_by(fn {row_num, _line, found} -> {map_size(found), -row_num} end, fn -> nil end)
    |> report(header)
  end

  defp sample(raw, within, nil), do: raw |> Enum.take(within) |> Enum.with_index(1)

  defp sample(raw, within, header_row),
    do: raw |> Enum.take(header_row + within - 1) |> Enum.with_index(1)

  defp candidate_lines(sample, nil), do: sample

  defp candidate_lines(sample, header_row),
    do: Enum.filter(sample, fn {_line, row_num} -> row_num == header_row end)

  defp rows_below(sample, row_num) do
    for {line, line_num} <- sample, line_num > row_num, not blank_line?(line), do: line
  end

  defp assign(line, %Header{columns: columns}, rules, rows) do
    line
    |> Enum.zip(Header.normalise_line(line))
    |> Enum.with_index()
    |> candidates(columns)
    |> Enum.reject(&fails_values?(&1, rules, rows))
    |> Enum.sort_by(fn {column, %Column{score: score, index: index}} ->
      {-score, index, column}
    end)
    |> Enum.reduce({%{}, %{}}, &take/2)
    |> add_values(line, rules, rows)
    |> add_counts(rules, rows)
  end

  defp candidates(cells, columns) do
    for {{cell, normalised}, index} <- cells,
        normalised != nil,
        {column, aliases} <- columns,
        target <- targets(column, aliases),
        is_binary(target),
        {via, score} <- List.wrap(evidence(cell, normalised, target)) do
      {column,
       %Column{passed: true, index: index, cell: cell, rule: target, via: via, score: score}}
    end
  end

  defp evidence(cell, normalised, target),
    do: evidence(normalised, target, words(cell), words(target))

  defp evidence(target, target, _cell_words, _target_words), do: {:alias, 1.0}
  defp evidence(_normalised, _target, [], _target_words), do: nil
  defp evidence(_normalised, _target, _cell_words, []), do: nil
  defp evidence(_normalised, _target, words, words), do: {:normalised, 0.95}

  defp evidence(_normalised, _target, cell_words, target_words),
    do: tokens_or_fuzzy(target_words -- cell_words, cell_words, target_words)

  defp tokens_or_fuzzy([], cell_words, target_words),
    do: {:tokens, 0.5 + 0.4 * length(target_words) / length(cell_words)}

  defp tokens_or_fuzzy(_missing, cell_words, target_words) do
    cell_words
    |> Enum.join()
    |> String.jaro_distance(Enum.join(target_words))
    |> fuzzy()
  end

  defp fuzzy(jaro) when jaro >= 0.9, do: {:fuzzy, 0.9 * jaro}
  defp fuzzy(_jaro), do: nil

  defp words(text) do
    ~r/([a-z0-9])([A-Z])/
    |> Regex.replace(text, "\\1 \\2")
    |> String.downcase()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
  end

  defp fails_values?({column, %Column{index: index}}, rules, rows) when is_map_key(rules, column),
    do: rules |> Map.fetch!(column) |> counts(rows, index) |> mostly_fails?()

  defp fails_values?(_candidate, _rules, _rows), do: false

  defp add_values({found, taken}, line, rules, rows) do
    rules
    |> Enum.reject(fn {column, _rule} -> is_map_key(found, column) end)
    |> Enum.sort()
    |> Enum.reduce({found, taken}, &add_value(&1, &2, line, rows))
    |> elem(0)
  end

  defp add_value({column, rule}, {_found, taken} = acc, line, rows) do
    line
    |> Enum.with_index()
    |> Enum.filter(fn {cell, index} -> free?(cell, index, taken) and fits?(rule, rows, index) end)
    |> claim(column, acc)
  end

  defp claim([{cell, index}], column, {found, taken}) do
    report = %Column{passed: true, index: index, cell: cell, via: :values, score: 0.4}

    {Map.put(found, column, report), Map.put(taken, index, true)}
  end

  defp claim(_fits, _column, acc), do: acc

  defp free?(cell, index, taken),
    do: is_binary(cell) and not blank?(cell) and not is_map_key(taken, index)

  defp fits?(rule, rows, index), do: rule |> counts(rows, index) |> mostly_passes?()

  defp add_counts(found, rules, rows),
    do: Map.new(found, fn {column, report} -> {column, counted(report, rules, column, rows)} end)

  defp counted(%Column{index: index} = report, rules, column, rows)
       when is_map_key(rules, column),
       do: %{report | rows: rules |> Map.fetch!(column) |> counts(rows, index)}

  defp counted(report, _rules, _column, _rows), do: report

  defp counts(rule, rows, index) do
    values = for row <- rows, value = Enum.at(row, index), not blank?(value), do: value

    {Enum.count(values, &Row.passes?(rule, &1)), length(values)}
  end

  defp mostly_fails?({passed, checked}), do: checked > 0 and passed * 2 < checked

  defp mostly_passes?({passed, checked}), do: checked > 0 and passed >= 0.95 * checked

  defp targets(column, aliases),
    do: Enum.uniq([normalise(column) | Enum.map(aliases, &normalise/1)])

  defp take({column, _report}, {found, _taken} = acc) when is_map_key(found, column), do: acc

  defp take({_column, %Column{index: index}}, {_found, taken} = acc)
       when is_map_key(taken, index), do: acc

  defp take({column, %Column{index: index} = report}, {found, taken}),
    do: {Map.put(found, column, report), Map.put(taken, index, true)}

  defp report(nil, header), do: report(nil, [], %{}, header)

  defp report({_row_num, _line, found}, header) when map_size(found) == 0,
    do: report(nil, [], %{}, header)

  defp report({row_num, line, found}, header), do: report(row_num, line, found, header)

  defp report(row_num, line, found, %Header{columns: columns} = header) do
    rules = Header.rules(header, Map.keys(found))

    %Line{
      row: row_num,
      check: :header,
      passed: Enum.all?(rules, & &1.passed),
      columns:
        Map.new(columns, fn {column, _aliases} -> {column, column_report(found, column)} end),
      rules: rules,
      extra: extra(line, found)
    }
  end

  defp column_report(found, column), do: Map.get(found, column, %Column{})

  defp extra(line, found) do
    taken = Map.new(found, fn {_column, %Column{index: index}} -> {index, true} end)

    for {cell, index} <- Enum.with_index(line),
        is_binary(cell),
        String.trim(cell) != "",
        not is_map_key(taken, index),
        do: {index, cell}
  end

  defp validate_within(within) when is_integer(within) and within > 0, do: :ok

  defp validate_within(within),
    do: raise(ArgumentError, "within must be a positive integer, got: #{inspect(within)}")

  defp validate_header_row(nil), do: :ok
  defp validate_header_row(header_row) when is_integer(header_row) and header_row > 0, do: :ok

  defp validate_header_row(header_row) do
    raise(
      ArgumentError,
      "header_row must be a positive integer or nil, got: #{inspect(header_row)}"
    )
  end
end
