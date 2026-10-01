defmodule Refract.E2E.BadDataTest do
  use ExUnit.Case, async: true

  @moduletag :e2e
  @moduletag :tmp_dir
  @moduletag timeout: 10_000

  alias Refract.CSV
  alias Refract.Golden
  alias Refract.Rows
  alias Refract.Table

  @input Golden.path("bad_data", "input.csv")

  test "skips to the header, selects and renames, drops blank rows", %{tmp_dir: dir} do
    out = Path.join(dir, "bad_data.csv")

    assert {:ok, rows} = CSV.stream(@input, skip: 3)

    assert :ok =
             rows
             |> Rows.select(%{"identifier" => "id", "name" => "name"})
             |> Stream.reject(&Rows.blank?/1)
             |> CSV.write(out, header: ["id", "name"])

    assert File.read!(out) == Golden.expected("bad_data")
  end

  test "locates the header and renames through the spec, drops blank rows", %{tmp_dir: dir} do
    out = Path.join(dir, "bad_data.csv")
    spec = Table.spec(header: [columns: %{"id" => ["identifier"], "name" => ["name"]}])

    assert {:ok, table} = CSV.locate(@input, spec)

    assert :ok =
             table.rows
             |> Stream.reject(&Rows.blank?/1)
             |> CSV.write(out, header: ["id", "name"])

    assert File.read!(out) == Golden.expected("bad_data")
  end
end
