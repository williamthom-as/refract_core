defmodule Refract.Classify.Mapping do
  @moduledoc false

  alias Refract.Classify.Mapping.Column

  defstruct [:header_row, columns: %{}, unmapped: [], extra: []]

  @type t :: %__MODULE__{
          header_row: pos_integer() | nil,
          columns: %{String.t() => Column.t()},
          unmapped: [String.t()],
          extra: [String.t()]
        }
end
