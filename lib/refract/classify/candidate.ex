defmodule Refract.Classify.Candidate do
  @moduledoc false

  alias Refract.Shape
  alias Refract.Table.Report.Line

  @type status :: :matched | :rows_failed | :no_header

  @type t :: %__MODULE__{
          shape: Shape.t(),
          status: status(),
          score: float(),
          header: Line.t() | nil,
          rows: [Line.t()]
        }

  defstruct [:shape, :status, :score, :header, rows: []]

  def new(shape, status, score, header, rows) do
    %__MODULE__{
      shape: shape,
      status: status,
      score: score,
      header: header,
      rows: rows
    }
  end
end
