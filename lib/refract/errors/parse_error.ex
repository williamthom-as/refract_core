defmodule Refract.Errors.ParseError do
  @moduledoc """
  raised by a reader stream on malformed input, eg an unclosed quote in a csv.
  `classify` and `load` return it as `{:error, {:parse_error, message}}` instead.
  `locate` does too while it finds the header, rows under it raise while streaming.
  """

  defexception [:message]

  @spec translate(Enumerable.t(), module()) :: Enumerable.t()

  def translate(stream, exception) do
    fn acc, fun -> guard(exception, fn -> Enumerable.reduce(stream, acc, fun) end) end
  end

  defp guard(exception, reduce) do
    exception
    |> continue(reduce.())
  rescue
    error -> translate_error(error, exception, __STACKTRACE__)
  end

  defp continue(exception, {:suspended, acc, next}) do
    {:suspended, acc, fn acc -> guard(exception, fn -> next.(acc) end) end}
  end

  defp continue(_exception, result), do: result

  defp translate_error(%exception{} = error, exception, stacktrace) do
    reraise __MODULE__, [message: Exception.message(error)], stacktrace
  end

  defp translate_error(error, _exception, stacktrace), do: reraise(error, stacktrace)
end
