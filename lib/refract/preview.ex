defmodule Refract.Preview do
  @max_cell_width 30

  @type print_opt ::
          {:limit, pos_integer()}
          | {:title, String.t()}
          | {:header, [String.t()]}

  @spec print(Enumerable.t(), [print_opt()]) :: :ok

  def print(rows, opts \\ []) do
    opts = Keyword.validate!(opts, [:title, :header, limit: 10])
    limit = Keyword.fetch!(opts, :limit)

    validate_limit(limit)

    candidate_rows = Enum.take(rows, limit + 1)
    selected_rows = Enum.take(candidate_rows, limit)

    if title = Keyword.get(opts, :title), do: IO.puts(title)

    print_table(selected_rows, Keyword.get(opts, :header))

    if length(candidate_rows) > limit do
      IO.puts("first #{limit} rows shown, more not shown")
    end

    :ok
  end

  defp validate_limit(limit) when is_integer(limit) and limit > 0, do: :ok

  defp validate_limit(limit) do
    raise ArgumentError, "limit must be a positive integer, got: #{inspect(limit)}"
  end

  defp print_table([], _header), do: IO.puts("no rows")

  defp print_table([first | _] = rows, header) do
    header = header || first |> Map.keys() |> Enum.sort()

    lines = Enum.map(rows, fn row -> Enum.map(header, &cell(Map.fetch!(row, &1))) end)
    widths = column_widths([header | lines])

    separator = separator(widths)

    IO.puts(separator)
    IO.puts(line(header, widths))
    IO.puts(separator)
    Enum.each(lines, &IO.puts(line(&1, widths)))
    IO.puts(separator)
  end

  defp column_widths(lines) do
    lines
    |> Enum.zip()
    |> Enum.map(fn column ->
      column |> Tuple.to_list() |> Enum.map(&String.length/1) |> Enum.max()
    end)
  end

  defp separator(widths),
    do: "+" <> Enum.map_join(widths, "+", &String.duplicate("-", &1 + 2)) <> "+"

  defp line(cells, widths) do
    "|" <>
      Enum.map_join(Enum.zip(cells, widths), "|", fn {cell, width} ->
        " " <> String.pad_trailing(cell, width) <> " "
      end) <> "|"
  end

  defp cell(nil), do: ""

  defp cell(value) do
    string = to_string(value)

    if String.length(string) > @max_cell_width do
      String.slice(string, 0, @max_cell_width - 3) <> "..."
    else
      string
    end
  end
end
