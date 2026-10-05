defmodule Refract.DoctestTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  doctest Refract.Parse
  doctest Refract.Clean
  doctest Refract.Privacy.Redact
end
