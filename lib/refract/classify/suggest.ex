defmodule Refract.Classify.Suggest do
  @moduledoc false

  alias Refract.Classify.Mapping
  alias Refract.Shape

  @type opt :: {:within, pos_integer()} | {:header_row, pos_integer() | nil}

  @spec run(Enumerable.t(), Shape.t() | module(), [opt()]) :: Mapping.t()
end
