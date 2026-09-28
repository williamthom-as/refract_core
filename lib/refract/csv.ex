defmodule Refract.CSV do
  use Refract.Reader

  alias Refract.CSV.Parsers
  alias Refract.CSV.Source

  @spec open(source :: Refract.source(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}

  def open(source, opts) do
    with {:ok, parser} <- Parsers.for_separator(Keyword.get(opts, :separator, ",")),
         {:ok, content} <- Source.open(source, opts) do
      {:ok,
       content
       |> parser.to_line_stream()
       |> Source.strip_bom()
       |> parser.parse_stream(skip_headers: false)}
    end
  end
end
