defmodule Refract.Privacy.GenTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  alias Refract.Privacy.Gen
  alias Refract.Privacy.Keyring

  @keyring Keyring.new!(keys: %{1 => :binary.copy(<<1>>, 32)})

  defp opts(extra \\ []), do: Keyword.merge([domain: :account, keyring: @keyring], extra)

  describe "digits/2" do
    test "output never changes for the same key, domain and value" do
      assert Gen.digits("123456789012", opts(length: 10)) == "8460171936"
    end

    test "always the requested length, zero padded" do
      assert Gen.digits("123456789012", opts(length: 12)) == "028460171936"

      for value <- ~w(a b c d e f g h i j) do
        assert Gen.digits(value, opts(length: 10)) =~ ~r/^[0-9]{10}$/
      end
    end

    test "different domains give different digits" do
      refute Gen.digits("123456789012", opts(length: 10)) ==
               Gen.digits("123456789012", opts(length: 10, domain: :instance_id))
    end

    test "length must be 1 to 76" do
      assert Gen.digits("a", opts(length: 1)) =~ ~r/^[0-9]$/
      assert Gen.digits("a", opts(length: 76)) =~ ~r/^[0-9]{76}$/

      for bad <- [0, 77, "10", nil] do
        assert_raise ArgumentError, fn -> Gen.digits("a", opts(length: bad)) end
      end
    end

    test "length, domain and keyring are required" do
      assert_raise KeyError, fn -> Gen.digits("a", opts()) end
      assert_raise KeyError, fn -> Gen.digits("a", length: 10, keyring: @keyring) end
      assert_raise KeyError, fn -> Gen.digits("a", length: 10, domain: :account) end
    end

    test "unknown option raises" do
      assert_raise ArgumentError, fn -> Gen.digits("a", opts(length: 10, lenght: 10)) end
    end
  end

  describe "hex/2" do
    test "output never changes for the same key, domain and value" do
      assert Gen.hex("i-0abc123def4567890", opts(length: 17, domain: :instance_id)) ==
               "0a4e9322a548e126e"
    end

    test "always the requested length in lowercase hex" do
      assert Gen.hex("a", opts(length: 64)) =~ ~r/^[0-9a-f]{64}$/
    end

    test "length must be 1 to 64" do
      for bad <- [0, 65] do
        assert_raise ArgumentError, fn -> Gen.hex("a", opts(length: bad)) end
      end
    end
  end

  describe "guid/2" do
    test "output never changes for the same key, domain and value" do
      assert Gen.guid("i-0abc123def4567890", opts(domain: :instance_id)) ==
               "0a4e9322-a548-4126-acb5-9205053391fe"
    end

    test "is a valid version 4 guid" do
      for value <- ~w(a b c d e) do
        assert Gen.guid(value, opts()) =~
                 ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
      end
    end

    test "domain and keyring are required" do
      assert_raise KeyError, fn -> Gen.guid("a", keyring: @keyring) end
    end
  end
end
