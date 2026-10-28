defmodule Refract.Profile.Column do
  @moduledoc false

  alias Refract.Profile.Cluster

  defstruct [:blanks, :distinct, capped: false, clusters: []]

  @type t :: %__MODULE__{
          blanks: non_neg_integer(),
          distinct: non_neg_integer() | nil,
          capped: boolean(),
          clusters: [Cluster.t()]
        }
end
