defmodule Refract.Validate.Issue do
  @moduledoc false

  alias Refract.Table.Spec.Row
  alias Refract.Validate.Rules

  defstruct [:line, :column, :field, :rule, :value]

  @type rule :: Rules.rule() | atom() | {:recognition, Row.rule() | atom()}

  @type t :: %__MODULE__{
          line: pos_integer() | nil,
          column: String.t() | nil,
          field: String.t() | nil,
          rule: rule(),
          value: Refract.cell() | nil
        }
end
