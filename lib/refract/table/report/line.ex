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

  def new(row, check, passed, columns, rules) do
    %__MODULE__{
      row: row,
      check: check,
      passed: passed,
      columns: columns,
      rules: rules
    }
  end

  @spec for_header(pos_integer() | nil, boolean(), %{String.t() => Column.t()}, [Rule.t()]) :: t()

  def for_header(row, passed, columns, rules) do
    new(row, :header, passed, columns, rules)
  end

  @spec for_row(pos_integer() | nil, boolean(), %{String.t() => Column.t()}, [Rule.t()]) :: t()

  def for_row(row, passed, columns, rules) do
    new(row, :row, passed, columns, rules)
  end

  @spec for_stop(pos_integer() | nil, boolean(), %{String.t() => Column.t()}, [Rule.t()]) :: t()

  def for_stop(row, passed, columns, rules) do
    new(row, :stop, passed, columns, rules)
  end
end
