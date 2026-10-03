defmodule Refract.PseudonymTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  alias Refract.Keyring
  alias Refract.Pseudonym

  @root_1 :binary.copy(<<1>>, 32)
  @root_2 :binary.copy(<<2>>, 32)

  defp keyring(opts \\ []), do: Keyring.new!(Keyword.merge([keys: %{1 => @root_1}], opts))

  describe "apply/4" do
    test "output never changes for the same key, domain and value" do
      assert Pseudonym.apply("1234567890", :instance_id, keyring()) == {:ok, "5256797815"}
    end

    test "keeps length and digits by default" do
      assert {:ok, pseudonym} = Pseudonym.apply("0012345678", :instance_id, keyring())
      assert pseudonym =~ ~r/^[0-9]{10}$/
    end

    test "different domains give different pseudonyms" do
      refute Pseudonym.apply("1234567890", :instance_id, keyring()) ==
               Pseudonym.apply("1234567890", :account, keyring())
    end

    test "atom and string domains are the same domain" do
      assert Pseudonym.apply("1234567890", :instance_id, keyring()) ==
               Pseudonym.apply("1234567890", "instance_id", keyring())
    end

    test "adding a key version leaves a pinned domain unchanged" do
      rotated = keyring(keys: %{1 => @root_1, 2 => @root_2}, pins: %{instance_id: 1})

      assert Pseudonym.apply("1234567890", :instance_id, rotated) == {:ok, "5256797815"}

      refute Pseudonym.apply("1234567890", :account, rotated) ==
               Pseudonym.apply("1234567890", :account, keyring())
    end

    test "named alphabets" do
      assert Pseudonym.apply("0abc123def4567890", :instance_id, keyring(), alphabet: :hex) ==
               {:ok, "ad05da4481495f351"}

      assert {:ok, base36} = Pseudonym.apply("ab12cd", :instance_id, keyring(), alphabet: :base36)
      assert base36 =~ ~r/^[0-9a-z]{6}$/

      assert {:ok, alnum} =
               Pseudonym.apply("Ab12Cd", :instance_id, keyring(), alphabet: :alphanumeric)

      assert alnum =~ ~r/^[0-9a-zA-Z]{6}$/
    end

    test "a custom alphabet string" do
      assert {:ok, pseudonym} =
               Pseudonym.apply("ACGTACGTAC", :instance_id, keyring(), alphabet: "ACGT")

      assert pseudonym =~ ~r/^[ACGT]{10}$/
    end

    test "characters outside the alphabet are an error" do
      assert Pseudonym.apply("12345a7890", :instance_id, keyring()) ==
               {:error, {:not_in_alphabet, "a"}}
    end

    test "canonical runs before encrypting so variants link" do
      opts = [canonical: &String.trim/1]

      assert Pseudonym.apply(" 1234567890 ", :instance_id, keyring(), opts) ==
               Pseudonym.apply("1234567890", :instance_id, keyring())
    end

    test "small domains are refused by default and allowed with min_domain" do
      assert Pseudonym.apply("1234", :instance_id, keyring()) ==
               {:error, {:domain_too_small, 10_000}}

      assert {:ok, _pseudonym} =
               Pseudonym.apply("1234", :instance_id, keyring(), min_domain: 100)
    end

    test "values that are not strings are an error" do
      assert Pseudonym.apply(1_234_567_890, :instance_id, keyring()) ==
               {:error, {:not_a_string, 1_234_567_890}}

      assert Pseudonym.apply(nil, :instance_id, keyring()) == {:error, {:not_a_string, nil}}
    end

    test "unknown alphabet raises" do
      assert_raise ArgumentError, fn ->
        Pseudonym.apply("1234567890", :instance_id, keyring(), alphabet: :emoji)
      end
    end

    test "unknown option raises" do
      assert_raise ArgumentError, fn ->
        Pseudonym.apply("1234567890", :instance_id, keyring(), alphabt: :hex)
      end
    end
  end

  describe "reverse/4" do
    test "gives back the original value" do
      assert Pseudonym.reverse("5256797815", :instance_id, keyring()) == {:ok, "1234567890"}
    end

    test "uses the same options as apply" do
      opts = [alphabet: :hex]
      {:ok, pseudonym} = Pseudonym.apply("0abc123def4567890", :instance_id, keyring(), opts)

      assert Pseudonym.reverse(pseudonym, :instance_id, keyring(), opts) ==
               {:ok, "0abc123def4567890"}
    end

    test "the wrong domain does not give back the original" do
      refute Pseudonym.reverse("5256797815", :account, keyring()) == {:ok, "1234567890"}
    end
  end

  describe "apply!/4 and reverse!/4" do
    test "return the value" do
      assert Pseudonym.apply!("1234567890", :instance_id, keyring()) == "5256797815"
      assert Pseudonym.reverse!("5256797815", :instance_id, keyring()) == "1234567890"
    end

    test "raise without putting the value in the message" do
      error =
        assert_raise ArgumentError, fn ->
          Pseudonym.apply!("12345a7890", :instance_id, keyring())
        end

      assert error.message =~ "not_in_alphabet"
      refute error.message =~ "12345a7890"
    end
  end
end
