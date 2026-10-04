defmodule Refract.Privacy.KeyedTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  alias Refract.Privacy.Keyed
  alias Refract.Privacy.Keyring

  @root_1 :binary.copy(<<1>>, 32)
  @root_2 :binary.copy(<<2>>, 32)

  defp keyring(opts \\ []), do: Keyring.new!(Keyword.merge([keys: %{1 => @root_1}], opts))

  describe "bytes/3" do
    test "output never changes for the same key, domain and value" do
      bytes = Keyed.bytes("i-0abc123def4567890", :instance_id, keyring())

      assert Base.encode16(bytes, case: :lower) ==
               "0a4e9322a548e126ecb59205053391fe4dbb71ad8b3743e33130540d1817abb3"
    end

    test "different values give different bytes" do
      refute Keyed.bytes("a", :instance_id, keyring()) ==
               Keyed.bytes("b", :instance_id, keyring())
    end

    test "different domains give different bytes" do
      refute Keyed.bytes("a", :instance_id, keyring()) == Keyed.bytes("a", :account, keyring())
    end

    test "is not the domain key used by pseudonyms" do
      {_version, key} = Keyring.key(keyring(), :instance_id)

      refute Keyed.bytes("a", :instance_id, keyring()) == :crypto.mac(:hmac, :sha256, key, "a")
    end

    test "values that are not strings use their string form" do
      assert Keyed.bytes(12_345, :account, keyring()) == Keyed.bytes("12345", :account, keyring())
    end

    test "a pinned domain keeps its bytes after a new key version" do
      rotated = keyring(keys: %{1 => @root_1, 2 => @root_2}, pins: %{instance_id: 1})

      assert Keyed.bytes("a", :instance_id, rotated) == Keyed.bytes("a", :instance_id, keyring())
    end
  end

  describe "integer/3" do
    test "is the bytes read as one unsigned integer" do
      bytes = Keyed.bytes("a", :instance_id, keyring())

      assert Keyed.integer("a", :instance_id, keyring()) == :binary.decode_unsigned(bytes)
    end
  end
end
