defmodule Refract.Validate.Check do
  @moduledoc false

  alias Refract.Parse
  alias Refract.Table.Spec.Row
  alias Refract.Validate.Rules

  import Refract.String.Utils, only: [blank?: 1, text: 1]
  import Refract.Utils, only: [truthy?: 1]

  @spec passes?(Rules.rule(), Refract.cell()) :: boolean()

  def passes?(:required, cell), do: not blank?(cell)
  def passes?({:min, %Date{} = bound}, cell), do: date_compare(cell, bound) in [:eq, :gt]
  def passes?({:max, %Date{} = bound}, cell), do: date_compare(cell, bound) in [:eq, :lt]
  def passes?({:min, bound}, cell), do: number_compare(cell, bound) in [:eq, :gt]
  def passes?({:max, bound}, cell), do: number_compare(cell, bound) in [:eq, :lt]
  def passes?({:in, values}, cell), do: text(cell) in Enum.map(values, &text/1)

  def passes?({name, fun}, cell) when is_atom(name) and is_function(fun, 1),
    do: holds?(fun, cell)

  def passes?(rule, cell), do: Row.passes?(rule, cell)

  @spec holds?((term() -> as_boolean(term())), term()) :: boolean()

  def holds?(fun, value) do
    truthy?(fun.(value))
  rescue
    _error -> false
  end

  defp number_compare(cell, bound),
    do: cell |> Parse.number(currency: true) |> compared(decimal(bound))

  defp date_compare(cell, bound), do: cell |> Parse.date() |> date_compared(bound)

  defp compared({:ok, value}, bound), do: Decimal.compare(value, bound)
  defp compared({:error, _reason}, _bound), do: :invalid

  defp date_compared({:ok, date}, bound), do: Date.compare(date, bound)
  defp date_compared({:error, _reason}, _bound), do: :invalid

  defp decimal(%Decimal{} = bound), do: bound
  defp decimal(bound) when is_integer(bound), do: Decimal.new(bound)
  defp decimal(bound) when is_float(bound), do: Decimal.from_float(bound)
end
