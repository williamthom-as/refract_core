defmodule Refract.Table.Report.Column do
  @moduledoc false

  alias Refract.Table.Spec.Row

  defstruct [:index, :cell, :rule, passed: false]

  @type rule :: String.t() | Row.rule()

  @type t :: %__MODULE__{
          passed: boolean(),
          index: non_neg_integer() | nil,
          cell: Refract.cell(),
          rule: rule() | nil
        }
end
