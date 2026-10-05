defmodule Refract.Rows.Ctx do
  @type t :: %__MODULE__{
          row: Refract.row(),
          column: String.t()
        }

  defstruct [:row, :column]

  @spec new(Refract.row(), String.t()) :: t()

  def new(row, column) do
    %__MODULE__{row: row, column: column}
  end
end
