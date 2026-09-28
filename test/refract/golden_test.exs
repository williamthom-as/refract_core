defmodule Refract.GoldenTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 10_000
  @moduletag :tmp_dir

  @golden Path.expand("../fixtures/golden", __DIR__)

  defp golden(name, file), do: Path.join([@golden, name, file])

  test "empty_columns (ruby cure empty_columns_spec)", %{tmp_dir: dir} do
    out = Path.join(dir, "empty_columns.csv")

    assert {:ok, rows} = Refract.CSV.stream(golden("empty_columns", "input.csv"))
    assert :ok = Refract.CSV.write(rows, out, header: ["identifier", "name", "col_2", "col_3"])

    assert File.read!(out) == File.read!(golden("empty_columns", "expected.csv"))
  end
end
