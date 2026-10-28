defmodule Refract.ProfileTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 10_000

  alias Refract.CSV
  alias Refract.Profile
  alias Refract.Profile.Cluster
  alias Refract.Profile.Column
  alias Refract.Profile.Result
  alias Refract.Profile.Variant
  alias Refract.Shape
  alias Refract.Table

  @columns %{
    "account" => ["account"],
    "cost_centre" => ["cost centre"],
    "amount" => ["amount"],
    "branch" => ["branch"]
  }

  @ledger {:string,
           """
           Ledger export

           Account,Cost Centre,Amount
           A-1,Cost Center 1,1.00
           A-2,costcenter1,2.00
           A-3,Cost Center 1,3.00
           A-4,cost center 1,4.00
           A-5,Cost Center 2,5.00
           A-6,,6.00
           A-7,costcenter1,7.00
           """}

  defp ledger(opts \\ []) do
    Shape.new(
      [
        name: "ledger",
        spec:
          Table.spec(
            header: [columns: @columns, required: ["account", "amount"], min_matches: 2],
            row: [match: %{"amount" => :number}]
          )
      ] ++ opts
    )
  end

  defp profile(source, opts \\ []) do
    assert {:ok, %Result{} = result} = CSV.profile(source, ledger(), opts)
    result
  end

  defp cost_centres(values, opts \\ []) do
    lines = Enum.map(values, &["A-1", &1, "1.00"])
    {:ok, result} = Profile.lines([["Account", "Cost Centre", "Amount"] | lines], ledger(), opts)
    result.columns["cost_centre"]
  end

  defp grouped(%Column{clusters: clusters}),
    do: Enum.map(clusters, fn %Cluster{variants: variants} -> Enum.map(variants, & &1.value) end)

  describe "clusters" do
    test "spellings of one value group with counts and file lines" do
      assert %Column{
               clusters: [
                 %Cluster{
                   most_common: "Cost Center 1",
                   via: :fingerprint,
                   variants: [
                     %Variant{value: "Cost Center 1", count: 2, lines: [4, 6]},
                     %Variant{value: "costcenter1", count: 2, lines: [5, 10]},
                     %Variant{value: "cost center 1", count: 1, lines: [7]}
                   ]
                 }
               ]
             } = profile(@ledger).columns["cost_centre"]
    end

    test "rows, blanks and distinct values" do
      assert %Result{rows: 7, columns: %{"cost_centre" => column}} = profile(@ledger)
      assert %Column{blanks: 1, distinct: 4, capped: false} = column
    end

    test "a value spelled one way is not a cluster" do
      assert %Column{distinct: 7, clusters: []} = profile(@ledger).columns["account"]
    end

    test "case, spacing, punctuation and accents group" do
      assert grouped(
               cost_centres(["Café", "cafe", "C-100", "c100", " North  Store ", "north store"])
             ) ==
               [["Café", "cafe"], ["C-100", "c100"], [" North  Store ", "north store"]]
    end

    test "different digits never group" do
      assert grouped(
               cost_centres([
                 "Cost Center 1 2",
                 "Cost Center 12",
                 "1.5",
                 "15",
                 "Store 1",
                 "Store 2"
               ])
             ) ==
               []
    end

    test "clusters by total count, variants by count then first seen" do
      values = ["north", "North", "south", "South", "SOUTH", "SOUTH", "south"]

      assert grouped(cost_centres(values)) == [["south", "SOUTH", "South"], ["north", "North"]]
    end

    test "the most common is the most frequent variant, ties to the first seen" do
      assert [%Cluster{most_common: "SOUTH"}] =
               cost_centres(["south", "SOUTH", "SOUTH"]).clusters

      assert [%Cluster{most_common: "south"}] = cost_centres(["south", "SOUTH"]).clusters
    end

    test "non text cells are compared as text" do
      {:ok, result} =
        Profile.lines(
          [["Account", "Cost Centre", "Amount"], ["A-1", 12, 1], ["A-2", "12", 2]],
          ledger()
        )

      assert grouped(result.columns["cost_centre"]) == [[12, "12"]]
    end
  end

  describe "columns" do
    test "a column with rules is profiled too" do
      shape = ledger(validation: [columns: %{"cost_centre" => [~r/^[A-Za-z ]+\d$/]}])

      assert {:ok, %Result{columns: %{"cost_centre" => %Column{clusters: [_cluster]}}}} =
               CSV.profile(@ledger, shape)
    end

    test "every column found in the file, none it lacks" do
      assert profile(@ledger).columns |> Map.keys() |> Enum.sort() ==
               ["account", "amount", "cost_centre"]
    end

    test "except leaves columns out" do
      assert profile(@ledger, except: ["account", "amount"]).columns |> Map.keys() ==
               ["cost_centre"]
    end

    test "except names shape columns" do
      assert_raise ArgumentError, ~r/except/, fn ->
        CSV.profile(@ledger, ledger(), except: ["notes"])
      end

      assert_raise ArgumentError, ~r/except/, fn ->
        CSV.profile(@ledger, ledger(), except: "notes")
      end
    end
  end

  describe "limits" do
    test "a column past max_distinct keeps its counts and has no clusters" do
      result = profile(@ledger, max_distinct: 4)

      assert %Column{capped: true, blanks: 0, clusters: []} = result.columns["account"]
      assert %Column{capped: false, clusters: [_cluster]} = result.columns["cost_centre"]
      assert %Column{capped: true} = profile(@ledger, max_distinct: 3).columns["cost_centre"]
    end

    test "max_lines keeps the first lines and the full count" do
      assert %Column{clusters: [%Cluster{variants: [%Variant{count: 2, lines: [4]} | _]}]} =
               profile(@ledger, max_lines: 1).columns["cost_centre"]
    end

    test "limits are positive integers" do
      for opts <- [[max_distinct: 0], [max_lines: 0], [max_distinct: "5"]] do
        assert_raise ArgumentError, fn -> CSV.profile(@ledger, ledger(), opts) end
      end
    end
  end

  describe "reading" do
    test "rows after a stop are not profiled" do
      shape =
        Shape.new(
          name: "ledger",
          spec: Table.spec(header: [columns: @columns, min_matches: 2], stop: [:blank])
        )

      source = {:string, "Account,Cost Centre\nA-1,north\nA-2,North\n\nA-3,NORTH\n"}

      assert {:ok, %Result{rows: 2, columns: %{"cost_centre" => column}}} =
               CSV.profile(source, shape)

      assert grouped(column) == [["north", "North"]]
    end

    test "rows failing recognition are still profiled" do
      source =
        {:string, "Account,Cost Centre,Amount\nA-1,north,1.00\nA-2,North,n/a\nA-3,NORTH,3.00\n"}

      assert %Result{rows: 3, columns: %{"cost_centre" => column}} = profile(source)
      assert grouped(column) == [["north", "North", "NORTH"]]
    end

    test "header_row picks the header" do
      assert %Result{rows: 7} = profile(@ledger, header_row: 3)
    end

    test "no header is an error" do
      assert {:error, {:header_not_found, _miss}} =
               CSV.profile({:string, "a,b\n1,2\n"}, ledger())
    end
  end
end
