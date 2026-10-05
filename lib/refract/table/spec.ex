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

  def new(opts) do
    opts = Keyword.validate!(opts, [:header, :row, :stop, :max_misses])

    header =
      case Keyword.fetch(opts, :header) do
        :error -> raise ArgumentError, "header is required"
        {:ok, header_opts} -> Header.new(header_opts)
      end

    row_opts = Keyword.get(opts, :row, [])
    row = Row.new(row_opts)

    validate_row_rules(row.match, header.columns)

    stop_opts = Keyword.get(opts, :stop, [])
    stop = Stop.new(stop_opts)

    max_misses = Keyword.get(opts, :max_misses, 0)

    validate_max_misses(max_misses)

    %__MODULE__{
      header: header,
      row: row,
      stop: stop,
      max_misses: max_misses
    }
  end

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
