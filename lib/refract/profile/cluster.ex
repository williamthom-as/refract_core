defmodule Refract.Profile.Cluster do
  @moduledoc false

  alias Refract.Profile.Variant

  defstruct [:most_common, :via, variants: []]

  @type t :: %__MODULE__{
          most_common: Refract.cell(),
          via: :normalised | :fuzzy,
          variants: [Variant.t()]
        }
end
