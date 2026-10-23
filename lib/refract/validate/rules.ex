defmodule Refract.Validate.Rules do
  @moduledoc false

  @type rule ::
          :required
          | :integer
          | :number
          | :date
          | :datetime
          | Regex.t()
          | {:min | :max, number() | Decimal.t() | Date.t()}
          | {:in, [term()]}
          | {atom(), (Refract.cell() -> as_boolean(term()))}
          | (Refract.cell() -> as_boolean(term()))

  @type row_rule :: {atom(), (Refract.row() -> as_boolean(term()))}

  @type t :: %__MODULE__{columns: %{String.t() => [rule()]}, rows: [row_rule()]}

  defstruct columns: %{}, rows: []

  @spec new!(keyword(), %{String.t() => term()}) :: t()

  def new!(opts, column_names) do
    opts = Keyword.validate!(opts, columns: %{}, rows: [])
    columns = Keyword.get(opts, :columns)
    rows = Keyword.get(opts, :rows)

    validate_columns(columns, column_names)
    Enum.each(rows, &validate_row_rule/1)

    %__MODULE__{columns: columns, rows: rows}
  end

  defp validate_columns(columns, column_names) do
    Enum.each(columns, fn {column, rules} ->
      validate_column(column, column_names)
      Enum.each(rules, &validate_rule/1)
    end)
  end

  defp validate_column(column, column_names) when is_map_key(column_names, column), do: :ok

  defp validate_column(column, _column_names) do
    raise ArgumentError, "validation rule for unknown column #{column}"
  end

  defp validate_rule(rule) when rule in [:required, :integer, :number, :date, :datetime], do: :ok
  defp validate_rule(%Regex{}), do: :ok
  defp validate_rule({bound, n}) when bound in [:min, :max] and is_number(n), do: :ok
  defp validate_rule({bound, %Decimal{}}) when bound in [:min, :max], do: :ok
  defp validate_rule({bound, %Date{}}) when bound in [:min, :max], do: :ok
  defp validate_rule({:in, values}) when is_list(values), do: :ok
  defp validate_rule({name, fun}) when is_atom(name) and is_function(fun, 1), do: :ok
  defp validate_rule(fun) when is_function(fun, 1), do: :ok

  defp validate_rule(rule) do
    raise ArgumentError, "unknown validation rule #{inspect(rule)}"
  end

  defp validate_row_rule({name, fun}) when is_atom(name) and is_function(fun, 1), do: :ok

  defp validate_row_rule(rule) do
    raise ArgumentError, "a row rule must be {name, fn row -> boolean end}, got: #{inspect(rule)}"
  end
end
