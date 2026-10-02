defmodule Refract.Pseudonym.FF1 do
  # nist sp 800-38g ff1, algorithm 7 encrypt, algorithm 8 decrypt
  #
  # reference impl:
  # https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Standards-and-Guidelines/documents/examples/FF1samples.pdf
  # see also:
  # https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-38G.pdf
  # https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-38Gr1.2pd.pdf

  @rounds 10

  @type error ::
          {:domain_too_small, pos_integer()}
          | {:not_in_alphabet, String.t()}
          | {:too_short, non_neg_integer()}

  # min_domain defaults to the nist sp 800-38g rev 1 line [1 mil], lower it to opt out
  @type opt :: {:min_domain, non_neg_integer()}

  @spec encrypt(binary(), binary(), String.t(), String.t(), [opt()]) ::
          {:ok, String.t()} | {:error, error()}

  def encrypt(key, tweak, alphabet, value, opts \\ []),
    do: run(:encrypt, key, tweak, alphabet, value, opts)

  @spec decrypt(binary(), binary(), String.t(), String.t(), [opt()]) ::
          {:ok, String.t()} | {:error, error()}

  def decrypt(key, tweak, alphabet, value, opts \\ []),
    do: run(:decrypt, key, tweak, alphabet, value, opts)

  defp run(direction, key, tweak, alphabet, value, opts) do
    opts = Keyword.validate!(opts, min_domain: 1_000_000)
    min_domain = Keyword.fetch!(opts, :min_domain)

    validate_min_domain(min_domain)

    {ecb, cbc} = ciphers(byte_size(key))
    symbols = String.graphemes(alphabet)
    radix = length(symbols)

    with {:ok, numerals} <- to_numerals(value, symbols),
         :ok <- check_length(length(numerals)),
         :ok <- check_domain(radix, length(numerals), min_domain) do
      ctx = %{key: key, tweak: tweak, radix: radix, ecb: ecb, cbc: cbc}

      {:ok, direction |> feistel(numerals, ctx) |> from_numerals(symbols)}
    end
  end

  defp ciphers(16), do: {:aes_128_ecb, :aes_128_cbc}
  defp ciphers(24), do: {:aes_192_ecb, :aes_192_cbc}
  defp ciphers(32), do: {:aes_256_ecb, :aes_256_cbc}
  defp ciphers(size), do: raise(ArgumentError, "key must be 16, 24 or 32 bytes, got: #{size}")

  defp to_numerals(value, symbols) do
    index = symbols |> Enum.with_index() |> Map.new()

    value
    |> String.graphemes()
    |> Enum.reduce_while({:ok, []}, fn char, {:ok, numerals} ->
      case Map.fetch(index, char) do
        {:ok, numeral} -> {:cont, {:ok, [numeral | numerals]}}
        :error -> {:halt, {:error, {:not_in_alphabet, char}}}
      end
    end)
    |> case do
      {:ok, numerals} -> {:ok, Enum.reverse(numerals)}
      error -> error
    end
  end

  defp from_numerals(numerals, symbols) do
    symbols = List.to_tuple(symbols)

    Enum.map_join(numerals, &elem(symbols, &1))
  end

  defp validate_min_domain(min_domain) when is_integer(min_domain) and min_domain >= 0, do: :ok

  defp validate_min_domain(min_domain) do
    raise ArgumentError, "min_domain must be a non negative integer, got: #{inspect(min_domain)}"
  end

  # the feistel split needs two halves, so this is mechanics not policy
  defp check_length(length) when length >= 2, do: :ok
  defp check_length(length), do: {:error, {:too_short, length}}

  defp check_domain(radix, length, min_domain) do
    domain = Integer.pow(radix, length)

    if domain >= min_domain, do: :ok, else: {:error, {:domain_too_small, domain}}
  end

  defp feistel(direction, numerals, ctx) do
    n = length(numerals)
    # step 1: u, v
    u = div(n, 2)
    v = n - u
    # step 2: a, b
    {a, b} = Enum.split(numerals, u)

    # step 3: b
    b_bytes = div(bit_length(Integer.pow(ctx.radix, v) - 1) + 7, 8)
    # step 4: d
    d = 4 * div(b_bytes + 3, 4) + 4
    # step 5: p
    p = <<1, 2, 1, ctx.radix::24, 10, rem(u, 256), n::32, byte_size(ctx.tweak)::32>>
    ctx = Map.merge(ctx, %{u: u, v: v, p: p, b_bytes: b_bytes, d: d})

    # step 6: rounds
    {a, b} =
      case direction do
        :encrypt ->
          Enum.reduce(0..(@rounds - 1), {a, b}, fn i, {a, b} ->
            # step 6.v: m
            m = half_length(i, ctx)

            # step 6.vi: c
            c =
              Integer.mod(
                to_integer(a, ctx.radix) + round_value(i, b, ctx),
                Integer.pow(ctx.radix, m)
              )

            # step 6.vii to 6.ix: C, a = b, b = C
            {b, to_numerals_of_length(c, m, ctx.radix)}
          end)

        :decrypt ->
          Enum.reduce((@rounds - 1)..0//-1, {a, b}, fn i, {a, b} ->
            # step 6.v: m
            m = half_length(i, ctx)

            # step 6.vi: c
            c =
              Integer.mod(
                to_integer(b, ctx.radix) - round_value(i, a, ctx),
                Integer.pow(ctx.radix, m)
              )

            # step 6.vii to 6.ix: C, b = a, a = C
            {to_numerals_of_length(c, m, ctx.radix), a}
          end)
      end

    # step 7: a || b
    a ++ b
  end

  defp half_length(round, ctx) when rem(round, 2) == 0, do: ctx.u
  defp half_length(_round, ctx), do: ctx.v

  defp round_value(round, half, ctx) do
    # step 6.i: q
    pad = Integer.mod(-byte_size(ctx.tweak) - ctx.b_bytes - 1, 16)

    q =
      <<ctx.tweak::binary, 0::size(pad * 8), round,
        to_integer(half, ctx.radix)::size(ctx.b_bytes * 8)>>

    # step 6.ii: r = prf(p || q)
    r = cbc_mac(ctx.p <> q, ctx)
    # step 6.iii and 6.iv: s, y
    <<y::size(ctx.d * 8), _rest::binary>> = stretch(r, ctx)

    y
  end

  # prf: aes cbc-mac, zero iv, last block
  defp cbc_mac(data, ctx) do
    encrypted = :crypto.crypto_one_time(ctx.cbc, ctx.key, <<0::128>>, data, true)

    binary_part(encrypted, byte_size(encrypted) - 16, 16)
  end

  # step 6.iii: s = r || ciph(r xor 1) || ciph(r xor 2) ..., first d bytes
  defp stretch(r, ctx) do
    blocks = div(ctx.d + 15, 16)

    Enum.reduce(1..(blocks - 1)//1, r, fn j, acc ->
      acc <> :crypto.crypto_one_time(ctx.ecb, ctx.key, :crypto.exor(r, <<j::128>>), true)
    end)
  end

  # num_radix
  defp to_integer(numerals, radix), do: Enum.reduce(numerals, 0, &(&2 * radix + &1))

  # str_m_radix
  defp to_numerals_of_length(integer, length, radix) do
    digits = Integer.digits(integer, radix)

    List.duplicate(0, length - length(digits)) ++ digits
  end

  defp bit_length(integer), do: integer |> Integer.digits(2) |> length()
end
