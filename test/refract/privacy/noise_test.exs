defmodule Refract.Privacy.NoiseTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  alias Refract.Privacy.Keyring
  alias Refract.Privacy.Noise

  @keyring Keyring.new!(keys: %{1 => :binary.copy(<<1>>, 32)})

  defp opts(extra \\ []) do
    Keyword.merge([seed: "i-0abc123def4567890", domain: :cost, keyring: @keyring], extra)
  end

  describe "relative/3" do
    test "output never changes for the same key, domain and seed" do
      assert Noise.relative(Decimal.new("120.50"), 0.05, opts()) == Decimal.new("117.78")
    end

    test "stays within the fraction" do
      for seed <- ~w(a b c d e f g h i j) do
        shifted = Noise.relative(1000, 0.05, opts(seed: seed))

        assert shifted >= 950 and shifted <= 1050
      end
    end

    test "the same seed shifts every value by the same fraction" do
      small = Noise.relative(Decimal.new("100.000000"), 0.05, opts())
      large = Noise.relative(Decimal.new("200.000000"), 0.05, opts())

      assert small |> Decimal.mult(2) |> Decimal.sub(large) |> Decimal.abs() |> Decimal.to_float() <=
               0.000002
    end

    test "different seeds shift differently" do
      refute Noise.relative(1000, 0.05, opts(seed: "a")) ==
               Noise.relative(1000, 0.05, opts(seed: "b"))
    end

    test "keeps the type of the value" do
      assert Noise.relative(100, 0.05, opts()) == 98
      assert is_float(Noise.relative(100.0, 0.05, opts()))
      assert %Decimal{} = Noise.relative(Decimal.new("100"), 0.05, opts())
    end

    test "decimals keep their places unless round is given" do
      assert Noise.relative(Decimal.new("120.50"), 0.05, opts()) == Decimal.new("117.78")
      assert Noise.relative(Decimal.new("120.50"), 0.05, opts(round: 0)) == Decimal.new("118")
    end

    test "a fraction of 0 changes nothing" do
      assert Noise.relative(Decimal.new("120.50"), 0, opts()) == Decimal.new("120.50")
    end

    test "seed, domain and keyring are required" do
      assert_raise KeyError, fn -> Noise.relative(100, 0.05, domain: :cost, keyring: @keyring) end
      assert_raise KeyError, fn -> Noise.relative(100, 0.05, seed: "a", keyring: @keyring) end
      assert_raise KeyError, fn -> Noise.relative(100, 0.05, seed: "a", domain: :cost) end
    end

    test "a negative fraction raises" do
      assert_raise ArgumentError, fn -> Noise.relative(100, -0.05, opts()) end
    end

    test "values that are not numbers raise" do
      for bad <- ["100", nil] do
        assert_raise ArgumentError, fn -> Noise.relative(bad, 0.05, opts()) end
      end
    end

    test "unknown option raises" do
      assert_raise ArgumentError, fn -> Noise.relative(100, 0.05, opts(rounding: 2)) end
    end
  end

  describe "absolute/3" do
    test "output never changes for the same key, domain and seed" do
      assert Noise.absolute(42, 3, opts()) == 41
    end

    test "stays within the amount" do
      for seed <- ~w(a b c d e f g h i j) do
        shifted = Noise.absolute(42, 3, opts(seed: seed))

        assert shifted >= 39 and shifted <= 45
      end
    end

    test "the same seed shifts every value by the same amount" do
      assert Noise.absolute(42, 3, opts()) - 42 == Noise.absolute(100, 3, opts()) - 100
    end
  end

  describe "round bounds" do
    test "round must be an integer from 0 to 6144" do
      for noise <- [&Noise.relative/3, &Noise.absolute/3], round <- [-1, 6145, 2.5, "2"] do
        assert_raise ArgumentError, ~r/round/, fn ->
          noise.(Decimal.new("1.5"), 0.05, opts(round: round))
        end
      end
    end

    test "round of 6144 is allowed" do
      assert %Decimal{exp: -6144} = Noise.relative(Decimal.new(0), 0.05, opts(round: 6144))
    end

    test "a decimal with more than 6144 places keeps 6144" do
      assert %Decimal{exp: -6144} = Noise.relative(Decimal.new(1, 15, -100_000), 0.05, opts())
    end
  end
end
