defmodule Refract.Classify.Facts do
  @moduledoc false

  @enforce_keys [:lines_sampled]

  defstruct [
    :path,
    :size,
    :lines_sampled,
    :above_header,
    blank_lines: 0,
    widths: %{},
    format: %{}
  ]

  @type t :: %__MODULE__{
          path: String.t() | nil,
          size: non_neg_integer() | :unknown | nil,
          lines_sampled: non_neg_integer(),
          above_header: non_neg_integer() | nil,
          blank_lines: non_neg_integer(),
          widths: %{optional(non_neg_integer()) => non_neg_integer()},
          format: %{optional(atom()) => term()}
        }
end
