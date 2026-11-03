defmodule Refract.Validate.CrossRow.Ctx do
  @moduledoc false

  @enforce_keys [:line, :failed, :values]

  defstruct [:line, :failed, :values]

  @type t :: %__MODULE__{
          line: pos_integer(),
          failed: MapSet.t(String.t() | nil),
          values: boolean()
        }
end
