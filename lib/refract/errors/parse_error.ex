defmodule Refract.Errors.ParseError do
  @moduledoc """
  raised by a reader stream on malformed input, eg an unclosed quote in a csv.
  `classify` and `load` return it as `{:error, {:parse_error, message}}` instead.
  `locate` does too while it finds the header, rows under it raise while streaming.
  """

  defexception [:message]
end
