defmodule Refract.Profile.Column do
  @moduledoc false

  alias Refract.Profile.Cluster
  alias Refract.Profile.Variant

  @enforce_keys [:blanks, :distinct]

  defstruct [:blanks, :distinct, :fuzzy, :values, capped: false, clusters: []]

  @type t :: %__MODULE__{
          blanks: non_neg_integer(),
          distinct: non_neg_integer() | nil,
          fuzzy: :done | :skipped | :off | nil,
          capped: boolean(),
          clusters: [Cluster.t()],
          values: [Variant.t()] | nil
        }
end
