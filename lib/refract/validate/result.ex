defmodule Refract.Validate.Result do
  @moduledoc false

  alias Refract.Validate.Issue

  defstruct valid: true, rows: 0, issues: []

  @type t :: %__MODULE__{
          valid: boolean(),
          rows: non_neg_integer(),
          issues: [Issue.t()]
        }
end
