defmodule Refract.Validate.Issue do
  @moduledoc """
  one validation problem: where (line, column or field), the rule that failed, the cell
  when validated with `values: true`, and the record a row issue is about when validated with
  `identify_by:` (the named columns and their values, shown whatever `values:` says)

  - `describe/1` reads it as one line of text

      iex> Refract.Validate.Issue.describe(%Refract.Validate.Issue{line: 3, column: "account", rule: :required})
      "line 3, account: is required"
  """

  alias Refract.Table.Spec.Row
  alias Refract.Validate.Rules

  import Refract.String.Utils, only: [text: 1]

  @enforce_keys [:rule]

  defstruct [:line, :column, :field, :rule, :value, :record, :first_line]

  @type rule ::
          Rules.rule()
          | atom()
          | {:recognition, Row.rule() | atom()}
          | {:unique, [String.t()]}
          | {:max_tracked, :unique | {:unique, [String.t()]}}

  @type t :: %__MODULE__{
          line: pos_integer() | nil,
          column: String.t() | nil,
          field: String.t() | nil,
          rule: rule(),
          value: Refract.cell() | nil,
          record: %{String.t() => Refract.cell()} | nil,
          first_line: pos_integer() | nil
        }

  @doc false
  @spec shown(boolean(), Refract.cell()) :: Refract.cell() | nil

  def shown(true, cell), do: cell
  def shown(false, _cell), do: nil

  @spec describe(t()) :: String.t()

  def describe(%__MODULE__{rule: rule, value: value, first_line: first_line} = issue),
    do: where(issue) <> rule_text(rule) <> got(value) <> first_seen(first_line)

  defp where(%__MODULE__{line: nil, field: nil}), do: ""
  defp where(%__MODULE__{line: nil, field: field}), do: "field #{field}: "
  defp where(%__MODULE__{column: nil, field: nil} = issue), do: "#{description(issue)}: "

  defp where(%__MODULE__{field: nil, column: column} = issue),
    do: "#{description(issue)}, #{column}: "

  defp where(%__MODULE__{line: line, field: field}), do: "line #{line}, field #{field}: "

  defp description(%__MODULE__{line: line, record: nil}), do: "line #{line}"

  defp description(%__MODULE__{line: line, record: record}),
    do: "line #{line} (#{record_text(record)})"

  defp record_text(record) do
    record
    |> Enum.sort()
    |> Enum.map_join(", ", fn {column, value} -> "#{column} #{text(value)}" end)
  end

  defp rule_text({:recognition, rule}), do: rule_text(rule)
  defp rule_text(:required), do: "is required"
  defp rule_text(:column_missing), do: "column is missing"
  defp rule_text(:integer), do: "must be an integer"
  defp rule_text(:number), do: "must be a number"
  defp rule_text(:date), do: "must be a date"
  defp rule_text(:datetime), do: "must be a datetime"

  defp rule_text({kind, formats}) when kind in [:date, :datetime] and is_list(formats),
    do: "#{rule_text(kind)} (#{Enum.join(formats, ", ")})"

  defp rule_text(%Regex{} = regex), do: "must match #{inspect(regex)}"
  defp rule_text({:min, bound}), do: "must be at least #{bound}"
  defp rule_text({:max, bound}), do: "must be at most #{bound}"
  defp rule_text({:above, bound}), do: "must be more than #{bound}"
  defp rule_text({:below, bound}), do: "must be less than #{bound}"
  defp rule_text({:in, values}), do: "must be one of #{Enum.join(values, ", ")}"
  defp rule_text(:unique), do: "must be unique"

  defp rule_text({:unique, columns}),
    do: "#{Enum.join(columns, " and ")} must be unique together"

  defp rule_text({:max_tracked, :unique}),
    do: "unique not checked past this point (more values matched than max_tracked)"

  defp rule_text({:max_tracked, {:unique, columns}}),
    do:
      "#{Enum.join(columns, " and ")} unique together not checked past this point " <>
        "(more values matched than max_tracked)"

  defp rule_text({module, _opts}) when is_atom(module), do: rule_text(module)
  defp rule_text(name) when is_atom(name), do: "fails #{name(name)}"

  defp name(atom), do: atom |> inspect() |> String.trim_leading(":")

  defp got(value) when value in [nil, ""], do: ""
  defp got(value), do: ", got #{inspect(value)}"

  defp first_seen(nil), do: ""
  defp first_seen(line), do: ", first on line #{line}"
end
