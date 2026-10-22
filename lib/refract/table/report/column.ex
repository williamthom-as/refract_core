defmodule Refract.Table.Report.Column do
  @moduledoc false

  alias Refract.Table.Spec.Row

  defstruct [:index, :cell, :rule, :via, :score, :rows, passed: false, others: []]

  @type rule :: String.t() | Row.rule()

  @type via :: :alias | :normalised | :tokens | :fuzzy | :values

  @type t :: %__MODULE__{
          passed: boolean(),
          index: non_neg_integer() | nil,
          cell: Refract.cell(),
          rule: rule() | nil,
          via: via() | nil,
          score: float() | nil,
          rows: {non_neg_integer(), non_neg_integer()} | nil,
          others: [{non_neg_integer(), Refract.cell()}]
        }
end
