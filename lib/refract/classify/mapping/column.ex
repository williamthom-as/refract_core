defmodule Refract.Classify.Mapping.Column do
  @moduledoc false

  defstruct [:cell, :index, :alias, :via, :score]

  @type via :: :alias | :normalised | :tokens | :fuzzy

  @type t :: %__MODULE__{
          cell: String.t(),
          index: non_neg_integer(),
          alias: String.t(),
          via: via(),
          score: float()
        }
end
