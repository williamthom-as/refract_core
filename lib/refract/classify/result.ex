defmodule Refract.Classify.Result do
  @moduledoc false

  alias Refract.Classify.Candidate
  alias Refract.Classify.Drift
  alias Refract.Classify.Facts
  alias Refract.Shape

  @type verdict :: :match | :ambiguous | :unknown

  @type reason ::
          :rows_failed | :no_header | :within_margin | :markers | :wider_header | :most_columns

  @type t :: %__MODULE__{
          verdict: verdict(),
          reason: reason() | nil,
          shape: Shape.t() | nil,
          file: Facts.t() | nil,
          drift: Drift.t() | nil,
          candidates: [Candidate.t()]
        }

  defstruct [:verdict, :reason, :shape, :file, :drift, candidates: []]
end
