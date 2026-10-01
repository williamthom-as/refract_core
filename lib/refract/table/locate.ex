defmodule Refract.Table.Locate do
  alias Refract.Table
  alias Refract.Table.Spec

  @type header_miss :: %{row: pos_integer(), matched: [String.t()], missing: [String.t()]} | nil

  @spec run(Enumerable.t(), Spec.t(), keyword()) ::
          {:ok, Table.t()} | {:error, {:header_not_found, header_miss()}}

  def run(raw, %Spec{} = spec, opts) do
    opts = validate_opts!(opts)
    within = Keyword.fetch!(opts, :within)
    on_miss = Keyword.fetch!(opts, :on_miss)

    case find_header(raw, spec, within) do
      {:error, best} ->
        {:error, {:header_not_found, best}}

      {:ok, header_row, positions} ->
        rows =
          raw
          |> Stream.drop(header_row)
          |> Stream.transform(0, fn row, misses_count ->
            spec
            |> Table.match_stop(row)
            |> handle_line(row, misses_count, spec, positions, on_miss)
          end)

        {:ok, Table.new(header_row, header_names(positions), positions, rows)}
    end
  end

  @spec validate_opts!(keyword()) :: keyword()

  def validate_opts!(opts) do
    opts = Keyword.validate!(opts, within: 100, on_miss: :skip)

    validate_within(Keyword.fetch!(opts, :within))
    validate_on_miss(Keyword.fetch!(opts, :on_miss))

    opts
  end

  defp validate_within(within) when is_integer(within) and within >= 0, do: :ok

  defp validate_within(within) do
    raise ArgumentError, "within must be a non negative integer, got: #{inspect(within)}"
  end

  defp validate_on_miss(on_miss) when on_miss in [:skip, :keep], do: :ok

  defp validate_on_miss(on_miss) do
    raise ArgumentError, "unknown on_miss: #{inspect(on_miss)}"
  end

  defp find_header(raw, spec, within) do
    results =
      raw
      |> Enum.take(within)
      |> Enum.with_index(1)
      |> Enum.map(fn {row, index} -> {index, Table.match_header(spec, row)} end)

    case Enum.find(results, &match?({_index, {:ok, _positions}}, &1)) do
      {index, {:ok, positions}} -> {:ok, index, positions}
      nil -> {:error, best_miss(results)}
    end
  end

  defp best_miss([]), do: nil

  defp best_miss(results) do
    {index, {:error, miss}} =
      Enum.max_by(results, fn {_index, {:error, miss}} -> length(miss.matched) end)

    Map.put(miss, :row, index)
  end

  defp header_names(positions) do
    positions
    |> Enum.sort_by(fn {_name, pos} -> pos end)
    |> Enum.map(fn {name, _pos} -> name end)
  end

  defp handle_line(
         {:stop, _condition},
         _row,
         misses_count,
         _spec,
         _positions,
         _on_miss
       ),
       do: {:halt, misses_count}

  defp handle_line(:continue, row, misses_count, spec, positions, on_miss) do
    mapped_row = Table.ordered_row(row, positions)

    case Table.match_row(spec, mapped_row) do
      :ok ->
        {[mapped_row], misses_count}

      {:error, _row_miss} ->
        new_misses_count = misses_count + 1

        if new_misses_count > spec.max_misses do
          {:halt, new_misses_count}
        else
          case on_miss do
            :skip -> {[], new_misses_count}
            :keep -> {[mapped_row], new_misses_count}
          end
        end
    end
  end
end
