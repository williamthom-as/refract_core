defmodule Refract.Conformance.CSVWriterTest do
  use Refract.Test.WriterCase,
    writer: Refract.CSV,
    read: fn path ->
      path |> File.read!() |> NimbleCSV.RFC4180.parse_string(skip_headers: false)
    end
end
