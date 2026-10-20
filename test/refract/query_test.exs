defmodule Refract.QueryTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 10_000

  alias Refract.Query

  describe "open/1" do
    @describetag :duckdb

    test "gives a session" do
      assert {:ok, query} = Query.open()
      assert is_struct(query, Query)
    end
  end

  describe "open/1 without duckdbex" do
    @describetag :without_duckdb

    test "is a missing dependency error" do
      assert {:error, {:missing_dependency, :duckdbex}} = Query.open()
    end

    test "open! names the missing dependency" do
      assert_raise ArgumentError, ~r/missing_dependency.*duckdbex/, fn -> Query.open!() end
    end
  end
end
