defmodule Refract.Rows do
  alias Refract.String.Utils

  @spec update(
          Enumerable.t(),
          String.t() | [String.t()],
          (Refract.cell() -> Refract.cell()),
          keyword()
        ) :: Enumerable.t()

  def update(rows, column, fun, opts \\ []) do
    skip_blank = Keyword.get(opts, :skip_blank, false)
    columns = List.wrap(column)

    Stream.map(rows, fn row ->
      Enum.reduce(columns, row, fn col, acc ->
        value = Map.fetch!(acc, col)

        if skip_blank and Utils.blank?(value) do
          acc
        else
          Map.put(acc, col, fun.(value))
        end
      end)
    end)
  end

  @spec take(Enumerable.t(), [String.t()]) :: Enumerable.t()

  def take(rows, candidate_columns) do
    Stream.map(rows, fn row ->
      candidate_columns
      |> Map.new(fn col -> {col, Map.fetch!(row, col)} end)
    end)
  end
end
