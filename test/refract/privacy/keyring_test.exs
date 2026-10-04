defmodule Refract.Privacy.KeyringTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  alias Refract.Privacy.Keyring

  @root_1 :binary.copy(<<1>>, 32)
  @root_2 :binary.copy(<<2>>, 32)

  defp keyring(opts \\ []), do: Keyring.new!(Keyword.merge([keys: %{1 => @root_1}], opts))

  describe "key/2" do
    test "derives a 32 byte key per domain with the current version" do
      assert {1, key} = Keyring.key(keyring(), :instance_id)
      assert byte_size(key) == 32
    end

    test "derivation never changes" do
      {1, key} = Keyring.key(keyring(), :instance_id)

      assert Base.encode16(key, case: :lower) ==
               "b055b24ab05f766534c54d9f1581e943f11d668d0fc8d53e47e160a23c366f44"
    end

    test "same domain gives the same key" do
      assert Keyring.key(keyring(), :account) == Keyring.key(keyring(), :account)
    end

    test "different domains give different keys" do
      refute Keyring.key(keyring(), :account) == Keyring.key(keyring(), :customer)
    end

    test "atom and string domains are the same domain" do
      assert Keyring.key(keyring(), :account) == Keyring.key(keyring(), "account")
    end

    test "the current version is the highest" do
      keyring = keyring(keys: %{1 => @root_1, 2 => @root_2})

      assert {2, _key} = Keyring.key(keyring, :account)
    end

    test "a pinned domain keeps its version" do
      keyring = keyring(keys: %{1 => @root_1, 2 => @root_2}, pins: %{account: 1})

      assert {1, _key} = Keyring.key(keyring, :account)
      assert {2, _key} = Keyring.key(keyring, :customer)
    end

    test "adding a version leaves a pinned domain's key unchanged" do
      before = Keyring.key(keyring(), :account)
      rotated = keyring(keys: %{1 => @root_1, 2 => @root_2}, pins: %{account: 1})

      assert Keyring.key(rotated, :account) == before
    end
  end

  describe "new!/1" do
    test "no keys raises" do
      assert_raise ArgumentError, fn -> Keyring.new!(keys: %{}) end
    end

    test "a root key under 32 bytes raises naming the version" do
      assert_raise ArgumentError, ~r/version 1/, fn ->
        Keyring.new!(keys: %{1 => :binary.copy(<<1>>, 31)})
      end
    end

    test "a pin to an unknown version raises" do
      assert_raise ArgumentError, fn -> keyring(pins: %{account: 2}) end
    end

    test "unknown option raises" do
      assert_raise ArgumentError, fn -> keyring(pin: %{}) end
    end
  end

  describe "from_provider!/3" do
    test "loads keys from a provider" do
      prefix = "REFRACT_TEST_KEY_#{System.unique_integer([:positive])}"
      System.put_env("#{prefix}_1", Base.encode64(@root_1))
      on_exit(fn -> System.delete_env("#{prefix}_1") end)

      keyring =
        Keyring.from_provider!(Refract.Privacy.KeyProvider.Env, [prefix: prefix], pins: %{})

      assert Keyring.key(keyring, :instance_id) == Keyring.key(keyring(), :instance_id)
    end

    test "a provider error raises" do
      assert_raise ArgumentError, ~r/no_keys/, fn ->
        Keyring.from_provider!(Refract.Privacy.KeyProvider.Env,
          prefix: "REFRACT_TEST_NOTHING_HERE"
        )
      end
    end
  end

  test "inspect never shows keys" do
    keyring = keyring(keys: %{1 => @root_1, 2 => @root_2})
    output = inspect(keyring)

    assert output == "#Refract.Privacy.Keyring<versions: [1, 2]>"
    refute output =~ Base.encode64(@root_1)
  end
end
