defmodule Refract.Classify.Ctx do
  @moduledoc false

  alias Refract.Table.Scan

  defstruct [:sample, :prepared, :min_score, :margin, :values, :name]

  @type t :: %__MODULE__{
          sample: [Refract.raw_row()],
          prepared: Scan.prepared(),
          min_score: number(),
          margin: number(),
          values: boolean(),
          name: String.t() | nil
        }
end
