defmodule Refract.CSV.Parsers do
  @moduledoc false

  NimbleCSV.define(Refract.CSV.Parsers.Comma,
    separator: ",",
    escape: "\"",
    reserved: [",", "\"", "\n", "\r"]
  )

  NimbleCSV.define(Refract.CSV.Parsers.Tab,
    separator: "\t",
    escape: "\"",
    reserved: ["\t", "\"", "\n", "\r"]
  )

  NimbleCSV.define(Refract.CSV.Parsers.Semicolon,
    separator: ";",
    escape: "\"",
    reserved: [";", "\"", "\n", "\r"]
  )

  NimbleCSV.define(Refract.CSV.Parsers.Pipe,
    separator: "|",
    escape: "\"",
    reserved: ["|", "\"", "\n", "\r"]
  )

  @spec for_separator(String.t()) :: {:ok, module()} | {:error, term()}

  def for_separator(","), do: {:ok, Refract.CSV.Parsers.Comma}

  def for_separator("\t"), do: {:ok, Refract.CSV.Parsers.Tab}

  def for_separator(";"), do: {:ok, Refract.CSV.Parsers.Semicolon}

  def for_separator("|"), do: {:ok, Refract.CSV.Parsers.Pipe}

  def for_separator(separator), do: {:error, {:unsupported_separator, separator}}
end
