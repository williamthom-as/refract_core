defmodule Refract.Privacy.Pseudonym.FF1Test do
  use ExUnit.Case, async: true
  use ExUnitProperties

  @moduletag timeout: 10_000

  alias Refract.Privacy.Pseudonym.FF1

  @digits "0123456789"
  @base36 "0123456789abcdefghijklmnopqrstuvwxyz"

  @k128 Base.decode16!("2B7E151628AED2A6ABF7158809CF4F3C")
  @k192 Base.decode16!("2B7E151628AED2A6ABF7158809CF4F3CEF4359D8D580AA4F")
  @k256 Base.decode16!("2B7E151628AED2A6ABF7158809CF4F3CEF4359D8D580AA4F7F036D6F04FC6A94")

  @tweak_10 Base.decode16!("39383736353433323130")
  @tweak_36 Base.decode16!("3737373770717273373737")

  @nist [
    {1, @k128, "", @digits, "0123456789", "2433477484"},
    {2, @k128, @tweak_10, @digits, "0123456789", "6124200773"},
    {3, @k128, @tweak_36, @base36, "0123456789abcdefghi", "a9tv40mll9kdu509eum"},
    {4, @k192, "", @digits, "0123456789", "2830668132"},
    {5, @k192, @tweak_10, @digits, "0123456789", "2496655549"},
    {6, @k192, @tweak_36, @base36, "0123456789abcdefghi", "xbj3kv35jrawxv32ysr"},
    {7, @k256, "", @digits, "0123456789", "6657667009"},
    {8, @k256, @tweak_10, @digits, "0123456789", "1001623463"},
    {9, @k256, @tweak_36, @base36, "0123456789abcdefghi", "xs8a0azh2avyalyzuwd"}
  ]

  describe "nist sp 800-38g ff1 samples" do
    for {sample, key, tweak, alphabet, plain, cipher} <- @nist do
      @key key
      @tweak tweak
      @alphabet alphabet
      @plain plain
      @cipher cipher

      test "sample #{sample} encrypts" do
        assert FF1.encrypt(@key, @tweak, @alphabet, @plain) == {:ok, @cipher}
      end

      test "sample #{sample} decrypts" do
        assert FF1.decrypt(@key, @tweak, @alphabet, @cipher) == {:ok, @plain}
      end
    end
  end

  describe "encrypt/4 and decrypt/4" do
    property "decrypt reverses encrypt and the output keeps length and alphabet" do
      check all(
              plain <- string(Enum.to_list(?0..?9), min_length: 6, max_length: 40),
              tweak <- binary(max_length: 16)
            ) do
        assert {:ok, cipher} = FF1.encrypt(@k128, tweak, @digits, plain)
        assert String.length(cipher) == String.length(plain)
        assert cipher =~ ~r/^[0-9]+$/
        assert FF1.decrypt(@k128, tweak, @digits, cipher) == {:ok, plain}
      end
    end

    test "leading zeros are kept" do
      assert {:ok, cipher} = FF1.encrypt(@k128, "", @digits, "0000001")
      assert String.length(cipher) == 7
    end

    test "the same input gives the same output" do
      assert FF1.encrypt(@k128, "", @digits, "123456789") ==
               FF1.encrypt(@k128, "", @digits, "123456789")
    end

    test "a different tweak gives a different output" do
      refute FF1.encrypt(@k128, "a", @digits, "123456789") ==
               FF1.encrypt(@k128, "b", @digits, "123456789")
    end

    test "a different key gives a different output" do
      refute FF1.encrypt(@k128, "", @digits, "123456789") ==
               FF1.encrypt(@k256, "", @digits, "123456789")
    end

    test "domains under a million values are refused" do
      assert FF1.encrypt(@k128, "", @digits, "12345") == {:error, {:domain_too_small, 100_000}}
      assert {:ok, _cipher} = FF1.encrypt(@k128, "", @digits, "123456")
      assert FF1.decrypt(@k128, "", @digits, "12345") == {:error, {:domain_too_small, 100_000}}
    end

    test "min_domain can be lowered for small codes" do
      assert {:ok, cipher} = FF1.encrypt(@k128, "", @digits, "1234", min_domain: 100)
      assert String.length(cipher) == 4
      assert FF1.decrypt(@k128, "", @digits, cipher, min_domain: 100) == {:ok, "1234"}
    end

    test "min_domain 0 turns the check off" do
      assert {:ok, _cipher} = FF1.encrypt(@k128, "", @digits, "12", min_domain: 0)
    end

    test "one character is always too short" do
      assert FF1.encrypt(@k128, "", @digits, "7", min_domain: 0) == {:error, {:too_short, 1}}
      assert FF1.encrypt(@k128, "", @digits, "", min_domain: 0) == {:error, {:too_short, 0}}
    end

    test "min_domain must be a non negative integer" do
      for bad <- [-1, 1.5, "100"] do
        assert_raise ArgumentError, fn ->
          FF1.encrypt(@k128, "", @digits, "123456", min_domain: bad)
        end
      end
    end

    test "unknown option raises" do
      assert_raise ArgumentError, fn -> FF1.encrypt(@k128, "", @digits, "123456", min: 0) end
    end

    test "characters outside the alphabet are refused" do
      assert FF1.encrypt(@k128, "", @digits, "12345a789") == {:error, {:not_in_alphabet, "a"}}
    end

    test "keys must be 16, 24 or 32 bytes" do
      assert_raise ArgumentError, fn -> FF1.encrypt(<<0::120>>, "", @digits, "123456") end
    end
  end
end
