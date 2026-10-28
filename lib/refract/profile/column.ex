defmodule Refract.Profile.Column do
  @moduledoc false

  alias Refract.Profile.Cluster

  defstruct [:blanks, :distinct, :fuzzy, capped: false, clusters: []]

  @type t :: %__MODULE__{
          blanks: non_neg_integer(),
          distinct: non_neg_integer() | nil,
          fuzzy: :done | :skipped | nil,
          capped: boolean(),
          clusters: [Cluster.t()]
        }
end
