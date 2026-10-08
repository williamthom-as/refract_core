defmodule Refract.Classify.Result do
  alias Refract.Classify.Candidate
  alias Refract.Shape

  @type t :: %__MODULE__{
          verdict: :match | :unknown | :mismatch,
          reason: nil | :rows_failed | :header_failed,
          shape: Shape.t(),
          file: String.t(),
          candidates: [Candidate.t()]
        }

  defstruct [:verdict, :reason, :shape, :file, candidates: []]
end
