defmodule Refract.Table.Spec do
  alias Refract.Table.Spec.Header
  alias Refract.Table.Spec.Row

  defstruct [:header, :row]

  @type t :: %__MODULE__{
          header: Header.t(),
          row: Row.t()
        }

  def new(opts) do
    opts = Keyword.validate!(opts, [:header, :row])

    header =
      case Keyword.fetch(opts, :header) do
        :error -> raise ArgumentError, "header is required"
        {:ok, header_opts} -> Header.new(header_opts)
      end

    row_opts = Keyword.get(opts, :row, [])
    row = Row.new(row_opts)

    validate_row_rules(row.match, header.columns)

    %__MODULE__{
      header: header,
      row: row
    }
  end

  defp validate_row_rules(rules, columns) do
    Enum.each(rules, fn {column, _rule} ->
      unless Map.has_key?(columns, column) do
        raise ArgumentError, "row rule for unknown column #{column}"
      end
    end)
  end
end
