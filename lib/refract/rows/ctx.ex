defmodule Refract.Rows.Ctx do
  @moduledoc """
  provided to row update funs, contains the column name targeted and row being updated.

      Refract.Rows.update(rows, "cost", fn value, ctx ->
        Refract.Privacy.Noise.relative(value, 0.05, seed: ctx.row["instance"], domain: :cost, keyring: keyring)
      end)
  """

  @type t :: %__MODULE__{
          row: Refract.row(),
          column: String.t()
        }

  @enforce_keys [:row, :column]

  defstruct [:row, :column]

  @spec new(Refract.row(), String.t()) :: t()

  def new(row, column) do
    %__MODULE__{row: row, column: column}
  end
end
