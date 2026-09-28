defmodule Refract.CSV.Parsers do
  NimbleCSV.define(Refract.CSV.Parsers.Comma, separator: ",", escape: "\"")

  NimbleCSV.define(Refract.CSV.Parsers.Tab, separator: "\t", escape: "\"")

  NimbleCSV.define(Refract.CSV.Parsers.Semicolon, separator: ";", escape: "\"")

  NimbleCSV.define(Refract.CSV.Parsers.Pipe, separator: "|", escape: "\"")

  @spec for_separator(String.t()) :: {:ok, module()} | {:error, term()}

  def for_separator(","), do: {:ok, Refract.CSV.Parsers.Comma}

  def for_separator("\t"), do: {:ok, Refract.CSV.Parsers.Tab}

  def for_separator(";"), do: {:ok, Refract.CSV.Parsers.Semicolon}

  def for_separator("|"), do: {:ok, Refract.CSV.Parsers.Pipe}

  def for_separator(separator), do: {:error, {:unsupported_separator, separator}}
end
