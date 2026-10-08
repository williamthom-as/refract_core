defmodule Refract.Classify.Candidate do
  alias Refract.Shape
  alias Refract.Table.Report.Line
  alias Refract.Table.Spec.Header

  @type t :: %__MODULE__{
          shape: Shape.t(),
          status: :match | :unknown | :mismatch,
          score: number(),
          header: Header.t(),
          rows: [Line.t()]
        }

  defstruct [:shape, :status, :score, :header, rows: []]
end
