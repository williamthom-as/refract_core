defmodule Refract.Profile.Result do
  @moduledoc false

  alias Refract.Profile.Column
  alias Refract.Shape

  @enforce_keys [:shape, :rows]

  defstruct [:shape, :rows, :files, columns: %{}]

  @type t :: %__MODULE__{
          shape: Shape.t(),
          rows: non_neg_integer(),
          files: [Path.t()] | nil,
          columns: %{String.t() => Column.t()}
        }
end
