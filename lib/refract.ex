defmodule Refract do
  @moduledoc false

  # communal types

  # data
  @type cell :: String.t() | number() | boolean() | Date.t() | DateTime.t() | nil
  @type raw_row :: [cell()]
  @type row :: %{optional(String.t()) => cell()}

  # inputs
  @type source :: Path.t() | {:string, binary()} | {:stream, Enumerable.t()}
end
