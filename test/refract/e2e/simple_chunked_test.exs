defmodule Refract.E2E.SimpleChunkedTest do
  use ExUnit.Case, async: true

  @moduletag :e2e
  @moduletag :tmp_dir
  @moduletag timeout: 5_000

  alias Refract.CSV
  alias Refract.Golden
  alias Refract.Privacy.Gen
  alias Refract.Privacy.Keyring
  alias Refract.Rows

  @keyring Keyring.new!(keys: %{1 => :binary.copy(<<1>>, 32)})

  test "replaces a column with 12 digits and writes 2 rows per file", %{tmp_dir: dir} do
    assert {:ok, rows} = CSV.stream(Golden.path("simple_chunked", "input.csv"))

    assert {:ok, [first, second]} =
             rows
             |> Rows.update(
               "test_column",
               &Gen.digits(&1, length: 12, domain: :test, keyring: @keyring)
             )
             |> CSV.write_chunks(dir,
               prefix: "default",
               rows_per_file: 2,
               header: ["test_column", "test_column2"]
             )

    assert Path.basename(first) == "default_1.csv"
    assert Path.basename(second) == "default_2.csv"

    assert {:ok, first_rows} = CSV.stream(first)
    assert {:ok, second_rows} = CSV.stream(second)

    first_rows = Enum.to_list(first_rows)
    second_rows = Enum.to_list(second_rows)

    assert length(first_rows) == 2
    assert length(second_rows) == 1

    for row <- first_rows ++ second_rows do
      assert row["test_column"] =~ ~r/^[0-9]{12}$/
      assert row["test_column2"] == "def"
    end
  end
end
