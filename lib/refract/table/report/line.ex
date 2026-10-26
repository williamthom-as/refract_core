defmodule Refract.Table.Report.Line do
  @moduledoc false

  alias Refract.Table.Report.Column
  alias Refract.Table.Report.Rule

  defstruct [:row, :check, :passed, columns: %{}, rules: [], extra: []]

  @type check :: :header | :row

  @type t :: %__MODULE__{
          row: pos_integer() | nil,
          check: check(),
          passed: boolean(),
          columns: %{String.t() => Column.t()},
          rules: [Rule.t()],
          extra: [{non_neg_integer(), Refract.cell()}]
        }
end
