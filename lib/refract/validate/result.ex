defmodule Refract.Validate.Result do
  @moduledoc """
  the result of the validation run (if the content passes, how many table rows checked, the
  field values read) and every issue found
  """

  alias Refract.Validate.Issue

  import Refract.String.Utils, only: [text: 1]

  defstruct valid: true, rows: 0, issues: [], fields: %{}

  @type t :: %__MODULE__{
          valid: boolean(),
          rows: non_neg_integer(),
          issues: [Issue.t()],
          fields: %{String.t() => Refract.cell()}
        }

  @spec to_map(t()) :: map()

  def to_map(%__MODULE__{valid: valid, rows: rows, fields: fields, issues: issues}) do
    %{
      valid: valid,
      rows: rows,
      fields: Map.new(fields, fn {name, cell} -> {name, text(cell)} end),
      issues: Enum.map(issues, &issue/1)
    }
  end

  defp issue(%Issue{line: line, column: column, field: field, rule: rule} = issue) do
    %{
      line: line,
      column: column,
      field: field,
      rule: inspect(rule),
      value: text(issue.value),
      record: record(issue.record),
      first_line: issue.first_line
    }
  end

  defp record(nil), do: nil
  defp record(record), do: Map.new(record, fn {column, value} -> {column, text(value)} end)
end
