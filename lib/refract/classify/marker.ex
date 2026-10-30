defmodule Refract.Classify.Marker do
  @moduledoc false

  @enforce_keys [:marker, :pattern]

  defstruct [:marker, :pattern, :against, passed: false]

  @type t :: %__MODULE__{
          marker: :file | :content,
          pattern: Regex.t(),
          against: String.t() | nil,
          passed: boolean()
        }
end
