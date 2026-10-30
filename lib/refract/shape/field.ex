defmodule Refract.Shape.Field do
  @moduledoc false

  alias Refract.Grid.Lookup
  alias Refract.Validate.Rules

  @enforce_keys [:label, :at]

  defstruct [:label, :at, take: :right, rules: []]

  @type t :: %__MODULE__{
          label: String.t() | Regex.t() | nil,
          at: String.t() | nil,
          take: :right | :below,
          rules: [Rules.rule()]
        }

  @spec new!(keyword()) :: t()

  def new!(opts) do
    opts = Keyword.validate!(opts, label: nil, at: nil, take: :right, rules: [])

    label = Keyword.fetch!(opts, :label)
    at = Keyword.fetch!(opts, :at)
    take = Keyword.fetch!(opts, :take)
    rules = Keyword.fetch!(opts, :rules)

    validate_find(label, at)
    validate_label(label)
    validate_at(at)
    Lookup.validate_take!(take)

    Rules.validate_rules!(rules)

    %__MODULE__{label: label, at: at, take: take, rules: rules}
  end

  defp validate_find(nil, nil) do
    raise ArgumentError, "a field needs a label: or an at: to be found by"
  end

  defp validate_find(label, at) when label != nil and at != nil do
    raise ArgumentError, "a field is found by a label: or an at:, not both"
  end

  defp validate_find(_label, _at), do: :ok

  defp validate_label(nil), do: :ok
  defp validate_label(label), do: Lookup.validate_label!(label)

  defp validate_at(nil), do: :ok
  defp validate_at(at), do: Lookup.validate_ref!(at)
end
