defmodule Refract.Errors.ParseError do
  @moduledoc """
  raised by a reader stream on malformed input, eg an unclosed quote in a csv.
  `classify`, `locate` and `load` return it as `{:error, {:parse_error, message}}` instead.
  """

  defexception [:message]
end
