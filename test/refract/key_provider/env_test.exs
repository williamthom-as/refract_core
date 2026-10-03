defmodule Refract.KeyProvider.EnvTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  alias Refract.KeyProvider.Env

  @root_1 :binary.copy(<<1>>, 32)
  @root_2 :binary.copy(<<2>>, 32)

  defp prefix, do: "REFRACT_TEST_KEY_#{System.unique_integer([:positive])}"

  defp put(name, value) do
    System.put_env(name, value)
    on_exit(fn -> System.delete_env(name) end)
  end

  test "reads numbered variables as versions" do
    prefix = prefix()
    put("#{prefix}_1", Base.encode64(@root_1))
    put("#{prefix}_2", Base.encode64(@root_2))

    assert Env.fetch(prefix: prefix) == {:ok, %{1 => @root_1, 2 => @root_2}}
  end

  test "ignores variables that only share the start of the prefix" do
    prefix = prefix()
    put("#{prefix}_1", Base.encode64(@root_1))
    put("#{prefix}_OTHER_2", Base.encode64(@root_2))
    put("#{prefix}X_3", Base.encode64(@root_2))

    assert Env.fetch(prefix: prefix) == {:ok, %{1 => @root_1}}
  end

  test "no variables is an error" do
    prefix = prefix()

    assert Env.fetch(prefix: prefix) == {:error, {:no_keys, prefix}}
  end

  test "a value that is not base64 is an error naming the variable" do
    prefix = prefix()
    put("#{prefix}_1", "not base64!")

    assert Env.fetch(prefix: prefix) == {:error, {:invalid_base64, "#{prefix}_1"}}
  end

  test "prefix defaults to REFRACT_KEY" do
    assert {:error, {:no_keys, "REFRACT_KEY"}} = Env.fetch([])
  end
end
