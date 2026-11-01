defmodule Refract.Conformance.ReaderCaseWithoutLoadTest do
  use Refract.Test.ReaderCase,
    reader: Refract.TestReaders.Memory,
    build: fn rows, _dir -> %Refract.TestReaders.Memory{lines: rows} end,
    load: false
end
