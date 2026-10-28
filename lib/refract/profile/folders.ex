defmodule Refract.Profile.Folders do
  @moduledoc false

  alias Refract.Profile.Result

  defstruct results: %{}, skipped: []

  @type t :: %__MODULE__{
          results: %{{String.t(), pos_integer()} => Result.t()},
          skipped: [{Path.t(), term()}]
        }
end
