defmodule Refract.E2E.SimpleTranslationsTest do
  use ExUnit.Case, async: true

  @moduletag :e2e
  @moduletag timeout: 5_000

  alias Refract.CSV
  alias Refract.Golden
  alias Refract.Privacy.Keyring
  alias Refract.Privacy.Pseudonym
  alias Refract.Rows

  @keyring Keyring.new!(keys: %{1 => :binary.copy(<<1>>, 32)})
  @letters "abcdefghijklmnopqrstuvwxyz"
  @opts [alphabet: @letters, min_domain: 0]

  @fruit ~w(fav_fruit fav_fruit_2 fav_fruit_3)
  @colour ~w(fav_colour fav_colour_2 fav_colour_3)

  def translate(rows) do
    rows
    |> Rows.update(@fruit, &Pseudonym.apply!(&1, :fruit, @keyring, @opts))
    |> Rows.update(@colour, &Pseudonym.apply!(&1, :colour, @keyring, @opts))
  end

  setup do
    {:ok, input} = CSV.stream(Golden.path("simple_translations", "input.csv"))

    input = Enum.to_list(input)

    %{input: input, output: input |> translate() |> Enum.to_list()}
  end

  test "every word is replaced and keeps its length", %{input: input, output: output} do
    for {original, translated} <- Enum.zip(input, output), column <- @fruit ++ @colour do
      refute translated[column] == original[column]
      assert String.length(translated[column]) == String.length(original[column])
      assert translated[column] =~ ~r/^[a-z]+$/
    end
  end

  test "the same word translates the same across columns and rows", %{output: output} do
    assert output
           |> Enum.flat_map(&(Map.take(&1, @fruit) |> Map.values()))
           |> Enum.uniq()
           |> length() ==
             1

    for row <- output do
      assert row |> Map.take(@colour) |> Map.values() |> Enum.uniq() |> length() == 1
    end
  end

  test "different words stay different", %{output: [first, second]} do
    refute first["fav_colour"] == second["fav_colour"]
  end

  test "ids are untouched", %{input: input, output: output} do
    assert Enum.map(output, & &1["id"]) == Enum.map(input, & &1["id"])
  end

  test "reverse gives back the original words", %{input: input, output: output} do
    for {original, translated} <- Enum.zip(input, output) do
      for column <- @fruit do
        assert Pseudonym.reverse!(translated[column], :fruit, @keyring, @opts) == original[column]
      end

      for column <- @colour do
        assert Pseudonym.reverse!(translated[column], :colour, @keyring, @opts) ==
                 original[column]
      end
    end
  end

  test "small words need min_domain lowered", %{input: [first | _]} do
    assert Pseudonym.apply(first["fav_colour"], :colour, @keyring, alphabet: @letters) ==
             {:error, {:domain_too_small, 17_576}}
  end
end
