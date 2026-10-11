defmodule Refract.Classify.Facts do

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
    path: String.t(),
    size: non_neg_integer(),
    lines_sampled: non_neg_integer(),
    above_header: non_neg_integer(),
    blank_lines: non_neg_integer(),
    widths: %{optional(non_neg_integer()) => non_neg_integer()},
    format: %{optional(non_neg_integer()) => %{optional(non_neg_integer()) => String.t()}}
  }

end
