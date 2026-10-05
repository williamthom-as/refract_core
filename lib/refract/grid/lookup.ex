defmodule Refract.Grid.Lookup do
  @moduledoc false

  alias Refract.Grid
  alias Refract.Reader.Header

  import Refract.String.Utils, only: [blank?: 1, normalise: 1]

  @spec table(Grid.t(), keyword()) :: [Refract.row()]

  def table(%Grid{rows: rows} = grid, opts) do
    opts = Keyword.validate!(opts, [:at])
    {start, finish} = corners(grid, opts[:at])

    case area(rows, start, finish) do
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

    area(rows, start, finish)
  end

  @type label :: String.t() | Regex.t()

  @type value_opt :: {:label, label()} | {:take, :right | :below}

  @spec value(Grid.t(), [value_opt()]) :: Refract.cell()

  def value(%Grid{rows: rows} = grid, opts) do
    opts = Keyword.validate!(opts, [:label, take: :right])

    label = Keyword.get(opts, :label)
    take = Keyword.get(opts, :take)

    validate_label(label)
    validate_take(take)

    case find_label(rows, normalise(label)) do
      nil -> nil
      {x, y} -> take |> fetch_next(grid, x, y) |> Enum.find(&(not blank?(&1)))
    end
  end

  @type block_opt :: {:after, label()} | {:until, :blank}

  @spec block(Grid.t(), [block_opt()]) :: [Refract.cell()] | nil

  def block(%Grid{rows: rows} = grid, opts) do
    opts = Keyword.validate!(opts, [:after, until: :blank])

    after_label = Keyword.get(opts, :after)
    until = Keyword.get(opts, :until)

    validate_label(after_label)
    validate_until(until)

    case find_label(rows, normalise(after_label)) do
      nil ->
        nil

      {x, y} ->
        :below
        |> fetch_next(grid, x, y)
        |> Enum.take_while(&(not stop?(until, &1)))
    end
  end

  # privates

  defp corners(%Grid{width: width, height: height}, nil),
    do: {{0, 0}, {width - 1, height - 1}}

  defp corners(_grid, range), do: parse_range(range)

  defp area(rows, {x1, y1}, {x2, y2}) do
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

  defp fetch_next(:right, %Grid{rows: rows, width: width}, x, y),
    do: for(x <- (x + 1)..(width - 1)//1, do: fetch(rows, x, y))

  defp fetch_next(:below, %Grid{rows: rows, height: height}, x, y),
    do: for(y <- (y + 1)..(height - 1)//1, do: fetch(rows, x, y))

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

  defp validate_label(label) when is_binary(label) or is_struct(label, Regex), do: label

  defp validate_label(label),
    do: raise(ArgumentError, "label must be a string or regex, got: #{inspect(label)}")

  defp validate_take(value) when value not in [:right, :below],
    do: raise(ArgumentError, "take must be :right or :below, got: #{inspect(value)}")

  defp validate_take(value), do: value

  defp validate_until(value) when value not in [:blank],
    do: raise(ArgumentError, "until must be :blank, got: #{inspect(value)}")

  defp validate_until(value), do: value

  @spec find_label(tuple(), label()) :: {non_neg_integer(), non_neg_integer()} | nil

  defp find_label(rows, label) do
    Enum.find_value(0..(tuple_size(rows) - 1)//1, fn y ->
      row = elem(rows, y)

      Enum.find_value(0..(tuple_size(row) - 1)//1, fn x ->
        cell = elem(row, x)

        if cell_matches_label?(cell, label), do: {x, y}
      end)
    end)
  end

  defp cell_matches_label?(cell, label) when is_struct(label, Regex) and is_binary(cell),
    do: Regex.match?(label, cell)

  defp cell_matches_label?(cell, label) when is_binary(label) and is_binary(cell),
    do: normalise(cell) == label

  defp cell_matches_label?(_cell, _label), do: false

  defp stop?(:blank, cell), do: blank?(cell)
end
