defmodule Refract.Profile.Variant do
  @moduledoc false

  defstruct [:value, :count, lines: []]

  @type t :: %__MODULE__{value: Refract.cell(), count: pos_integer(), lines: [pos_integer()]}
end
