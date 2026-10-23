defmodule Refract.Validate.Issue do
  @moduledoc false

  alias Refract.Table.Spec.Row
  alias Refract.Validate.Rules

  defstruct [:line, :column, :rule, :value]

  @type rule :: Rules.rule() | atom() | {:recognition, Row.rule()}

  @type t :: %__MODULE__{
          line: pos_integer(),
          column: String.t() | nil,
          rule: rule(),
          value: Refract.cell() | nil
        }
end
