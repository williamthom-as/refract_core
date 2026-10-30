defmodule Refract.Table.Spec.Stop do
  @moduledoc false

  import Refract.String.Utils, only: [blank_line?: 1]
  import Refract.Utils, only: [truthy?: 1]

  @enforce_keys [:conditions]

  defstruct [:conditions]

  @type condition :: :blank | {:contains, Regex.t()} | (Refract.raw_row() -> as_boolean(term()))

  @type conditions :: [condition()]

  @type t :: %__MODULE__{
          conditions: conditions()
        }

  @spec new(conditions()) :: t()

  def new(conditions) do
    validate_conditions(conditions)

    %__MODULE__{
      conditions: conditions
    }
  end

  defp validate_conditions(conditions) when is_list(conditions) do
    Enum.each(conditions, fn condition ->
      if not valid_condition?(condition) do
        raise ArgumentError, "invalid stop condition: #{inspect(condition)}"
      end
    end)
  end

  defp validate_conditions(_), do: raise(ArgumentError, "stop must be a list")

  defp valid_condition?(:blank), do: true
  defp valid_condition?({:contains, %Regex{}}), do: true
  defp valid_condition?(fun) when is_function(fun, 1), do: true
  defp valid_condition?(_), do: false

  @spec matches(t(), Refract.raw_row()) :: :continue | {:stop, condition()}

  def matches(%__MODULE__{conditions: conditions}, row) do
    case Enum.find(conditions, &stop_condition_met?(&1, row)) do
      nil -> :continue
      condition -> {:stop, condition}
    end
  end

  defp stop_condition_met?(:blank, row), do: blank_line?(row)

  defp stop_condition_met?({:contains, regex}, row),
    do: Enum.any?(row, &(is_binary(&1) and Regex.match?(regex, &1)))

  defp stop_condition_met?(fun, row) when is_function(fun, 1), do: truthy?(fun.(row))
end
