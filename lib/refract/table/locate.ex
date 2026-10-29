defmodule Refract.Table.Locate do
  @moduledoc false

  alias Refract.ArgValidator
  alias Refract.Reader
  alias Refract.Table
  alias Refract.Table.Body
  alias Refract.Table.Report
  alias Refract.Table.Spec
  alias Refract.Table.Spec.Header

  @type header_miss :: %{row: pos_integer(), matched: [String.t()], missing: [String.t()]} | nil

  @spec run(Enumerable.t(), Spec.t(), keyword()) ::
          {:ok, Table.t()} | {:error, {:header_not_found, header_miss()}}

  def run(raw, %Spec{} = spec, opts) do
    opts = validate_opts!(opts)
    on_miss = Keyword.fetch!(opts, :on_miss)

    with {:ok, header_row, positions, steps} <-
           body(raw, spec, Keyword.take(opts, Keyword.keys(header_options()))) do
      {:ok, table(steps, spec, header_row, positions, on_miss)}
    end
  end

  @spec header_options() :: keyword()

  def header_options, do: [within: 100, header_row: nil]

  @spec options() :: keyword()

  def options, do: [on_miss: :skip] ++ header_options()

  @spec header(Enumerable.t(), Spec.t(), keyword()) ::
          {:ok, pos_integer(), Header.positions()} | {:error, {:header_not_found, header_miss()}}

  def header(raw, %Spec{} = spec, opts) do
    with {:ok, report} <- scan(raw, spec, opts) do
      {:ok, report.row, Header.positions(report)}
    end
  end

  defp scan(raw, spec, opts) do
    opts = Keyword.validate!(opts, header_options())
    within = Keyword.fetch!(opts, :within)
    header_row = Keyword.fetch!(opts, :header_row)

    validate_within!(within)
    validate_header_row!(header_row)

    raw
    |> find_header(spec, within, header_row)
    |> header_found()
  end

  @spec body(Enumerable.t(), Spec.t(), keyword()) ::
          {:ok, pos_integer(), Header.positions(), Enumerable.t(Body.step())}
          | {:error, {:header_not_found, header_miss()}}

  def body(raw, %Spec{} = spec, opts) do
    {body_opts, opts} = Keyword.split(opts, [:misses, :indexing])
    {columns, header_opts} = Keyword.pop(opts, :columns, :shape)

    with {:ok, report} <- scan(raw, spec, header_opts) do
      positions = positions(report, raw, columns)

      {:ok, report.row, positions, Body.run(raw, report.row, spec, positions, false, body_opts)}
    end
  end

  defp positions(report, _raw, :shape), do: Header.positions(report)

  defp positions(%Report.Line{row: row, columns: columns, extra: extra} = report, raw, :all) do
    named = Header.positions(report)
    names = raw |> Enum.at(row - 1) |> Reader.Header.names()

    unnamed =
      Enum.map(extra, &elem(&1, 0)) ++
        for {_name, %Report.Column{others: others}} <- columns,
            {index, _cell} <- others,
            do: index

    Enum.reduce(unnamed, named, &Map.put_new(&2, Enum.at(names, &1), &1))
  end

  @spec absent(Spec.t(), Header.positions()) :: %{String.t() => nil}

  def absent(spec, positions), do: spec |> missing_columns(positions) |> Map.new(&{&1, nil})

  defp table(steps, spec, header_row, positions, on_miss) do
    missing = missing_columns(spec, positions)
    absent = absent(spec, positions)

    rows =
      steps
      |> Stream.take_while(&in_table?/1)
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
    opts = Keyword.validate!(opts, options())

    validate_within!(Keyword.fetch!(opts, :within))
    validate_on_miss(Keyword.fetch!(opts, :on_miss))
    validate_header_row!(Keyword.fetch!(opts, :header_row))

    opts
  end

  @spec validate_within!(term()) :: :ok

  def validate_within!(within), do: ArgValidator.validate_non_negative_integer!(within, :within)

  @spec validate_header_row!(term()) :: :ok

  def validate_header_row!(nil), do: :ok
  def validate_header_row!(header_row) when is_integer(header_row) and header_row > 0, do: :ok

  def validate_header_row!(header_row) do
    raise ArgumentError,
          "header_row must be a positive integer or nil, got: #{inspect(header_row)}"
  end

  defp validate_on_miss(on_miss) when on_miss in [:skip, :keep], do: :ok

  defp validate_on_miss(on_miss) do
    raise ArgumentError, "unknown on_miss: #{inspect(on_miss)}"
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

  defp header_found({:error, best}), do: {:error, {:header_not_found, best}}

  defp header_found(found), do: found

  defp first_passing(scanned) do
    case Enum.find(scanned, & &1.passed) do
      nil -> {:error, best_miss(scanned)}
      report -> {:ok, report}
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

  defp in_table?({:end, _row, _report}), do: false
  defp in_table?(_step), do: true

  defp kept({:hit, row, _report}, _on_miss), do: [row]
  defp kept({:miss, row, _report}, :keep), do: [row]
  defp kept(_step, _on_miss), do: []
end
