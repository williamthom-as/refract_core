defmodule Refract.Classify.Suggest do
  @moduledoc false

  alias Refract.Shape

  alias Refract.Table.Report.Column
  alias Refract.Table.Report.Line

  alias Refract.Table.Spec.Header

  import Refract.String.Utils, only: [normalise: 1]

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

    raw
    |> candidate_lines(within, header_row)
    |> Enum.map(fn {line, row_num} -> {row_num, line, assign(line, header)} end)
    |> Enum.max_by(fn {row_num, _line, found} -> {map_size(found), -row_num} end, fn -> nil end)
    |> report(header)
  end

  defp candidate_lines(raw, within, nil), do: raw |> Enum.take(within) |> Enum.with_index(1)

  defp candidate_lines(raw, _within, header_row) do
    raw
    |> Stream.drop(header_row - 1)
    |> Enum.take(1)
    |> Enum.map(&{&1, header_row})
  end

  defp assign(line, %Header{columns: columns}) do
    line
    |> Enum.zip(Header.normalise_line(line))
    |> Enum.with_index()
    |> candidates(columns)
    |> Enum.sort_by(fn {column, %Column{score: score, index: index}} ->
      {-score, index, column}
    end)
    |> Enum.reduce({%{}, %{}}, &take/2)
    |> elem(0)
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
