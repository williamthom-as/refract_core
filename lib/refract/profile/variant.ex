defmodule Refract.Profile.Variant do
  @moduledoc false

  @enforce_keys [:value, :count]

  defstruct [:value, :count, :files, lines: []]

  @type t :: %__MODULE__{
          value: Refract.cell(),
          count: pos_integer(),
          lines: [pos_integer()],
          files: %{Path.t() => [pos_integer()]} | nil
        }
end
