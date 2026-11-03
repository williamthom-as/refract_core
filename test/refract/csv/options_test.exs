defmodule Refract.CSV.OptionsTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 10_000

  alias Refract.CSV

  @source {:string, "id,name\n1,alice\n"}

  test "open_options lists the separator and the encoding" do
    assert CSV.open_options() == [separator: :detect, encoding: :auto]
  end

  test "encode_options lists the header, separator, bom and formula escaping" do
    assert CSV.encode_options() == [
             header: nil,
             separator: ",",
             bom: false,
             escape_formulas: true
           ]
  end

  test "facts takes open's options and refuses others" do
    assert {:ok, %{delimiter: ";"}} = CSV.facts({:string, "id;name\n1;alice\n"}, separator: ";")
    assert_raise ArgumentError, fn -> CSV.facts(@source, sheet: "Jul") end
  end
end
