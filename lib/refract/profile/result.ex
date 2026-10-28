defmodule Refract.Profile.Result do
  @moduledoc false

  alias Refract.Profile.Column

  defstruct [:rows, columns: %{}]

  @type t :: %__MODULE__{rows: non_neg_integer(), columns: %{String.t() => Column.t()}}
end
