defmodule Refract.Table.Report.Line do
  @moduledoc false

  alias Refract.Table.Report.Column
  alias Refract.Table.Report.Rule

  defstruct [:row, :check, :passed, columns: %{}, rules: []]

  @type check :: :header | :row | :stop

  @type t :: %__MODULE__{
          row: pos_integer() | nil,
          check: check(),
          passed: boolean(),
          columns: %{String.t() => Column.t()},
          rules: [Rule.t()]
        }
end
