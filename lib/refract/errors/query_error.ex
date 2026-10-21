defmodule Refract.Errors.QueryError do
  @moduledoc """
  raised by a query run that fails
  """

  defexception [:message]
end
