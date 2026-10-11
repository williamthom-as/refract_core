defmodule Refract.Classify.Result do
  @moduledoc false

  alias Refract.Classify.Candidate
  alias Refract.Classify.Facts
  alias Refract.Shape

  @type verdict :: :match | :ambiguous | :unknown

  @type reason :: :rows_failed | :no_header | :within_margin

  @type t :: %__MODULE__{
          verdict: verdict(),
          reason: reason() | nil,
          shape: Shape.t() | nil,
          file: map() | nil,
          candidates: [Candidate.t()],
          file: Facts.t() | nil
        }

  defstruct [:verdict, :reason, :shape, :file, candidates: []]
end
