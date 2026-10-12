defmodule Refract.Table.Locate do
  @moduledoc false

  alias Refract.Table
  alias Refract.Table.Body
  alias Refract.Table.Spec
  alias Refract.Table.Spec.Header

  @type header_miss :: %{row: pos_integer(), matched: [String.t()], missing: [String.t()]} | nil

  @spec run(Enumerable.t(), Spec.t(), keyword()) ::
          {:ok, Table.t()} | {:error, {:header_not_found, header_miss()}}

  def run(raw, %Spec{} = spec, opts) do
    opts = validate_opts!(opts)
    within = Keyword.fetch!(opts, :within)
    on_miss = Keyword.fetch!(opts, :on_miss)
    header_row = Keyword.fetch!(opts, :header_row)

    case find_header(raw, spec, within, header_row) do
      {:error, best} ->
        {:error, {:header_not_found, best}}

      {:ok, header_row, positions} ->
        {:ok, table(raw, spec, header_row, positions, on_miss)}
    end
  end

  defp table(raw, spec, header_row, positions, on_miss) do
    missing = missing_columns(spec, positions)
    absent = Map.new(missing, &{&1, nil})

    rows =
      raw
      |> Stream.with_index(1)
      |> Stream.drop(header_row)
      |> Body.run(spec, positions, false)
      |> Stream.flat_map(&kept(&1, on_miss))
      |> Stream.map(&Map.merge(&1, absent))

    Table.new(header_row, header_names(positions) ++ missing, positions, rows)
  end

  defp missing_columns(%Spec{header: header}, positions) do
    header.columns
    |> Map.keys()
    |> Enum.reject(&Map.has_key?(positions, &1))
    |> Enum.sort()
  end

  @spec validate_opts!(keyword()) :: keyword()

  def validate_opts!(opts) do
    opts = Keyword.validate!(opts, within: 100, on_miss: :skip, header_row: nil)

    validate_within(Keyword.fetch!(opts, :within))
    validate_on_miss(Keyword.fetch!(opts, :on_miss))
    validate_header_row(Keyword.fetch!(opts, :header_row))

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

  defp validate_header_row(nil), do: :ok
  defp validate_header_row(header_row) when is_integer(header_row) and header_row > 0, do: :ok

  defp validate_header_row(header_row) do
    raise ArgumentError, "header_row must be a positive integer, got: #{inspect(header_row)}"
  end

  defp find_header(raw, spec, within, nil) do
    raw
    |> Enum.take(within)
    |> Table.scan(spec)
    |> first_passing()
  end

  defp find_header(raw, spec, _within, header_row) do
    raw
    |> Stream.drop(header_row - 1)
    |> Enum.take(1)
    |> Table.scan(spec)
    |> Enum.map(&%{&1 | row: header_row})
    |> first_passing()
  end

  defp first_passing(scanned) do
    case Enum.find(scanned, & &1.passed) do
      nil -> {:error, best_miss(scanned)}
      report -> {:ok, report.row, Header.positions(report)}
    end
  end

  defp best_miss([]), do: nil

  defp best_miss(results) do
    best = Enum.max_by(results, &Header.matched_count/1)

    %{
      row: best.row,
      matched: Map.keys(Header.positions(best)),
      missing: Header.required_missing(best)
    }
  end

  defp header_names(positions) do
    positions
    |> Enum.sort_by(fn {_name, pos} -> pos end)
    |> Enum.map(fn {name, _pos} -> name end)
  end

  defp kept({:hit, row, _report}, _on_miss), do: [row]
  defp kept({:miss, row, _report}, :keep), do: [row]
  defp kept(_step, _on_miss), do: []
end
