defmodule Refract.Query.Result do
  @moduledoc """
  the result of `Refract.Query.run/3`: `columns` (select order), `rows` are lazy stream of maps
  """

  defstruct [:columns, :rows]

  @type t :: %__MODULE__{
          columns: [String.t()],
          rows: Enumerable.t()
        }
end
