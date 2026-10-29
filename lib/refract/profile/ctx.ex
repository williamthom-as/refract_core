defmodule Refract.Profile.Ctx do
  @moduledoc false

  defstruct [
    :max_distinct,
    :max_lines,
    except: [],
    values: false,
    fuzzy: 0.94,
    columns: :shape,
    header_opts: []
  ]

  @type t :: %__MODULE__{
          max_distinct: pos_integer(),
          max_lines: pos_integer(),
          except: [String.t()],
          values: boolean(),
          fuzzy: number() | false,
          columns: :shape | :all,
          header_opts: keyword()
        }
end
