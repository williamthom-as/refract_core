defmodule Refract.Grid.Lookup do
  alias Refract.Grid
  alias Refract.Reader.Header

  @spec table(Grid.t(), keyword()) :: [Refract.row()]

  def table(%Grid{rows: rows} = grid, opts) do
    opts = Keyword.validate!(opts, [:at])
    {start, finish} = corners(grid, opts[:at])

    case block(rows, start, finish) do
      [] -> []
      [header_row | data] -> to_rows(Header.normalise(header_row), data)
    end
  end

  @spec cell(Grid.t(), String.t()) :: Refract.cell()

  def cell(%Grid{rows: rows}, ref) do
    {x, y} = parse_ref(ref)

    fetch(rows, x, y)
  end

  @spec range(Grid.t(), String.t()) :: [Refract.raw_row()]

  def range(%Grid{rows: rows}, range) do
    {start, finish} = parse_range(range)

    block(rows, start, finish)
  end

  # privates

  defp corners(%Grid{width: width, height: height}, nil),
    do: {{0, 0}, {width - 1, height - 1}}

  defp corners(_grid, range), do: parse_range(range)

  defp block(rows, {x1, y1}, {x2, y2}) do
    for y <- y1..y2//1 do
      for x <- x1..x2//1, do: fetch(rows, x, y)
    end
  end

  defp to_rows(header, data), do: Enum.map(data, &Header.to_row(header, &1))

  defp fetch(rows, x, y) when y < tuple_size(rows) do
    row = elem(rows, y)

    if x < tuple_size(row), do: elem(row, x)
  end

  defp fetch(_rows, _x, _y), do: nil

  defp parse_range(range) when is_binary(range) do
    with [from, to] <- String.split(range, ":"),
         {x1, y1} = start <- parse_ref(from),
         {x2, y2} = finish when x1 <= x2 and y1 <= y2 <- parse_ref(to) do
      {start, finish}
    else
      _ -> invalid_range(range)
    end
  end

  defp parse_range(range), do: invalid_range(range)

  defp parse_ref(ref) when is_binary(ref) do
    ref
    |> String.upcase()
    |> column(0, ref)
  end

  defp parse_ref(ref), do: invalid_ref(ref)

  defp column(<<letter, rest::binary>>, col, ref) when letter in ?A..?Z do
    column(rest, col * 26 + (letter - ?A + 1), ref)
  end

  defp column(<<digit, _::binary>> = digits, col, ref) when col > 0 and digit in ?1..?9 do
    case Integer.parse(digits) do
      {row, ""} -> {col - 1, row - 1}
      _ -> invalid_ref(ref)
    end
  end

  defp column(<<_::binary>>, _col, ref), do: invalid_ref(ref)

  defp invalid_range(range),
    do:
      raise(
        ArgumentError,
        "invalid range #{inspect(range)}, expected top left to bottom right like \"A4:G10\""
      )

  defp invalid_ref(ref),
    do:
      raise(
        ArgumentError,
        "invalid cell ref #{inspect(ref)}, expected a column and row like \"B4\""
      )
end
