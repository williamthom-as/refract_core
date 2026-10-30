defmodule Refract.Profile.Ctx do
  @moduledoc false

  @enforce_keys [:max_distinct, :max_lines]

  defstruct [
    :max_distinct,
    :max_lines,
    except: [],
    values: false,
    fuzzy: 0.94,
    columns: :shape,
    indexing: :lines,
    header_opts: []
  ]

  @type t :: %__MODULE__{
          max_distinct: pos_integer(),
          max_lines: pos_integer(),
          except: [String.t()],
          values: boolean(),
          fuzzy: number() | false,
          columns: :shape | :all,
          indexing: :lines | :records,
          header_opts: keyword()
        }
end
