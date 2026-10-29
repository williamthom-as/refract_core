defmodule Refract.Profile.Ctx do
  @moduledoc false

  defstruct [
    :max_distinct,
    :max_lines,
    except: [],
    singles: :keep,
    columns: :shape,
    header_opts: []
  ]

  @type t :: %__MODULE__{
          max_distinct: pos_integer(),
          max_lines: pos_integer(),
          except: [String.t()],
          singles: :keep | :drop,
          columns: :shape | :all,
          header_opts: keyword()
        }
end
