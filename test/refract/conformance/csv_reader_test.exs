defmodule Refract.Conformance.CSVReaderTest do
  use Refract.Test.ReaderCase,
    reader: Refract.CSV,
    build: fn rows, dir ->
      path = Path.join(dir, "source.csv")
      File.write!(path, NimbleCSV.RFC4180.dump_to_iodata(rows))
      path
    end
end
