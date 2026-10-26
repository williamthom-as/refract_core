defmodule Refract.Table.Spec do
  @moduledoc false

  alias Refract.Table.Spec.Header
  alias Refract.Table.Spec.Row
  alias Refract.Table.Spec.Stop

  defstruct [:header, :row, :stop, :max_misses]

  @type t :: %__MODULE__{
          header: Header.t(),
          row: Row.t(),
          stop: Stop.t(),
          max_misses: non_neg_integer()
        }

  @spec new(keyword()) :: t()

  def new(opts) do
    opts = Keyword.validate!(opts, [:header, row: [], stop: [], max_misses: 0])

    header = opts |> Keyword.fetch(:header) |> header()
    row = Row.new(Keyword.fetch!(opts, :row))

    validate_row_rules(row.match, header.columns)

    stop = Stop.new(Keyword.fetch!(opts, :stop))
    max_misses = Keyword.fetch!(opts, :max_misses)

    validate_max_misses(max_misses)

    %__MODULE__{
      header: header,
      row: row,
      stop: stop,
      max_misses: max_misses
    }
  end

  defp header({:ok, header_opts}), do: Header.new(header_opts)
  defp header(:error), do: raise(ArgumentError, "header is required")

  defp validate_row_rules(rules, columns) do
    Enum.each(rules, fn {column, _rule} ->
      if not Map.has_key?(columns, column) do
        raise ArgumentError, "row rule for unknown column #{column}"
      end
    end)
  end

  defp validate_max_misses(max_misses) when is_integer(max_misses) and max_misses >= 0, do: :ok

  defp validate_max_misses(_),
    do: raise(ArgumentError, "max_misses must be a non negative integer")
end
