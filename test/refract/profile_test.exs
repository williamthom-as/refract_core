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

  defp grouped(%Column{clusters: clusters}) do
    for %Cluster{variants: [_, _ | _] = variants} <- clusters, do: Enum.map(variants, & &1.value)
  end

  describe "clusters" do
    test "spellings of one value group with counts and file lines" do
      assert %Column{
               clusters: [
                 %Cluster{
                   most_common: "Cost Center 1",
                   via: :normalised,
                   variants: [
                     %Variant{value: "Cost Center 1", count: 2, lines: [4, 6]},
                     %Variant{value: "costcenter1", count: 2, lines: [5, 10]},
                     %Variant{value: "cost center 1", count: 1, lines: [7]}
                   ]
                 },
                 %Cluster{
                   most_common: "Cost Center 2",
                   variants: [%Variant{count: 1, lines: [8]}]
                 }
               ]
             } = profile(@ledger).columns["cost_centre"]
    end

    test "a result names its shape, a variant has lines, not files" do
      assert %Result{
               shape: %Shape{name: "ledger"},
               files: nil,
               columns: %{"cost_centre" => column}
             } =
               profile(@ledger)

      assert %Column{clusters: [%Cluster{variants: [%Variant{files: nil} | _]} | _]} = column
    end

    test "rows, blanks and distinct values" do
      assert %Result{rows: 7, columns: %{"cost_centre" => column}} = profile(@ledger)
      assert %Column{blanks: 1, distinct: 4, capped: false} = column
    end

    test "a value spelled one way is a cluster of one" do
      assert %Column{distinct: 7, clusters: clusters} = profile(@ledger).columns["account"]

      assert Enum.map(clusters, &{&1.most_common, &1.via, length(&1.variants)}) ==
               for(n <- 1..7, do: {"A-#{n}", :normalised, 1})
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

  describe "fuzzy" do
    test "a misspelling joins the cluster of the most common" do
      column = cost_centres(["Cost Center 1", "Cost Center 1", "costcenter1", "Cost Centre 1"])

      assert [%Cluster{most_common: "Cost Center 1", via: :fuzzy}] = column.clusters
      assert grouped(column) == [["Cost Center 1", "costcenter1", "Cost Centre 1"]]
    end

    test "transposed and dropped letters group" do
      assert grouped(cost_centres(["Melbourne", "Melbounre", "Marketing", "Markting"])) ==
               [["Melbourne", "Melbounre"], ["Marketing", "Markting"]]
    end

    test "different words stay apart" do
      values = [
        "North Sydney",
        "North Ryde",
        "Sales North",
        "Sales South",
        "Accounts Payable",
        "Accounts Receivable"
      ]

      assert grouped(cost_centres(values)) == []
    end

    test "short codes stay apart" do
      assert grouped(cost_centres(["NSW", "NWS", "QLD", "OLD", "abcde", "abced"])) == []
    end

    test "different digits never join" do
      assert grouped(cost_centres(["Cost Centre 1", "Cost Center 2"])) == []
    end

    test "a value joins only when close to the most common, not to another variant" do
      assert grouped(cost_centres(["Warehouse", "Warehouse", "Warehous", "Warhous"])) ==
               [["Warehouse", "Warehous"]]
    end

    test "a normalised cluster stays normalised when nothing joins it" do
      column = cost_centres(["north", "North"])

      assert %Column{fuzzy: :done, clusters: [%Cluster{via: :normalised}]} = column
    end

    test "too many groups to compare skips the fuzzy pass, normalised clusters stay" do
      values = Enum.map(1..501, &"item #{&1}") ++ ["north", "North", "Melbourne", "Melbounre"]

      assert %Column{fuzzy: :skipped} = column = cost_centres(values)
      assert grouped(column) == [["north", "North"]]
    end
  end

  describe "columns" do
    test "a column with rules is profiled too" do
      shape = ledger(validation: [columns: %{"cost_centre" => [~r/^[A-Za-z ]+\d$/]}])

      assert {:ok, %Result{columns: %{"cost_centre" => %Column{clusters: [_cluster, _single]}}}} =
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

  describe "columns: :all" do
    test "profiles header cells the shape does not name" do
      source =
        {:string,
         "Account,Cost Centre,Amount,Notes,Cost Centre,Notes\nA-1,north,1.00,ok,x,p\nA-2,North,2.00,OK,y,q\n"}

      assert {:ok, %Result{columns: columns}} = CSV.profile(source, ledger(), columns: :all)

      assert columns |> Map.keys() |> Enum.sort() ==
               ["Cost Centre (2)", "Notes", "Notes (2)", "account", "amount", "cost_centre"]

      assert grouped(columns["Notes"]) == [["ok", "OK"]]
      assert %Column{distinct: 2} = columns["Cost Centre (2)"]
    end

    test "columns: :all with except by header text" do
      source = {:string, "Account,Cost Centre,Amount,Notes\nA-1,north,1.00,ok\n"}

      assert {:ok, %Result{columns: columns}} =
               CSV.profile(source, ledger(), columns: :all, except: ["Notes", "account"])

      assert columns |> Map.keys() |> Enum.sort() == ["amount", "cost_centre"]
    end

    test "columns names a mode" do
      assert_raise ArgumentError, ~r/columns/, fn ->
        CSV.profile(@ledger, ledger(), columns: :file)
      end
    end
  end

  describe "limits" do
    test "a column past max_distinct keeps its counts and has no clusters" do
      result = profile(@ledger, max_distinct: 4)

      assert %Column{capped: true, blanks: 0, clusters: []} = result.columns["account"]
      assert %Column{capped: false, clusters: [_cluster, _single]} = result.columns["cost_centre"]
      assert %Column{capped: true} = profile(@ledger, max_distinct: 3).columns["cost_centre"]
    end

    test "max_lines keeps the first lines and the full count" do
      assert %Column{clusters: [%Cluster{variants: [%Variant{count: 2, lines: [4]} | _]} | _]} =
               profile(@ledger, max_lines: 1).columns["cost_centre"]
    end

    test "singles: :drop keeps only values spelt more than one way" do
      assert [%Cluster{most_common: "Cost Center 1"}] =
               profile(@ledger, singles: :drop).columns["cost_centre"].clusters

      assert %Column{clusters: []} = profile(@ledger, singles: :drop).columns["account"]

      assert_raise ArgumentError, ~r/singles/, fn ->
        CSV.profile(@ledger, ledger(), singles: :all)
      end
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
