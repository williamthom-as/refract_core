defmodule Refract.Privacy.Redact do
  @type mask_opt ::
          {:keep_first, non_neg_integer()}
          | {:keep_last, non_neg_integer()}
          | {:char, String.t()}

  @spec blank(term()) :: String.t()

  def blank(_value), do: ""

  @spec mask(term(), [mask_opt()]) :: String.t() | nil

  def mask(value, opts \\ [])

  def mask(nil, _opts), do: nil

  def mask(value, opts) do
    opts = Keyword.validate!(opts, keep_first: 0, keep_last: 0, char: "*")

    keep_first = Keyword.fetch!(opts, :keep_first)
    keep_last = Keyword.fetch!(opts, :keep_last)
    char = Keyword.fetch!(opts, :char)

    validate_keep(keep_first)
    validate_keep(keep_last)
    validate_char(char)

    value
    |> to_string()
    |> String.graphemes()
    |> masked(keep_first, keep_last, char)
  end

  defp masked(graphemes, keep_first, keep_last, char) do
    size = length(graphemes)
    hidden = size - keep_first - keep_last

    if hidden <= 0 do
      String.duplicate(char, size)
    else
      Enum.join(Enum.take(graphemes, keep_first)) <>
        String.duplicate(char, hidden) <>
        Enum.join(Enum.take(graphemes, -keep_last))
    end
  end

  defp validate_keep(keep) when is_integer(keep) and keep >= 0, do: :ok

  defp validate_keep(keep) do
    raise ArgumentError,
          "keep_first and keep_last must be non negative integers, got: #{inspect(keep)}"
  end

  defp validate_char(char) do
    if not (is_binary(char) and String.length(char) == 1) do
      raise ArgumentError, "char must be one character, got: #{inspect(char)}"
    end
  end
end
