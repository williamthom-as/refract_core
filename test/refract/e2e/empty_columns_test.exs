defmodule Refract.E2E.EmptyColumnsTest do
  use ExUnit.Case, async: true

  @moduletag :e2e
  @moduletag :tmp_dir
  @moduletag timeout: 10_000

  alias Refract.Golden

  test "empty_columns (ruby cure empty_columns_spec)", %{tmp_dir: dir} do
    out = Path.join(dir, "empty_columns.csv")

    assert {:ok, rows} = Refract.CSV.stream(Golden.path("empty_columns", "input.csv"))
    assert :ok = Refract.CSV.write(rows, out, header: ["identifier", "name", "col_2", "col_3"])

    assert File.read!(out) == Golden.expected("empty_columns")
  end
end
