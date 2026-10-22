defmodule Refract.Table.Report.Column do
  @moduledoc false

  alias Refract.Table.Spec.Row

  defstruct [:index, :cell, :rule, passed: false, others: []]

  @type rule :: String.t() | Row.rule()

  @type t :: %__MODULE__{
          passed: boolean(),
          index: non_neg_integer() | nil,
          cell: Refract.cell(),
          rule: rule() | nil,
          others: [{non_neg_integer(), Refract.cell()}]
        }
end
