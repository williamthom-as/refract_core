defmodule Refract.Table.Spec.Header do
  defstruct [:columns, :required, :min_matches]

  import Refract.String.Utils, only: [normalise: 1]

  @type t :: %__MODULE__{
          columns: %{String.t() => [String.t() | Regex.t()]},
          required: [String.t()],
          min_matches: non_neg_integer()
        }

  def new(opts) do
    opts = Keyword.validate!(opts, [:columns, :min_matches, required: []])

    columns =
      case Keyword.fetch(opts, :columns) do
        :error ->
          raise ArgumentError, "header columns are required"

        {:ok, columns} when not is_map(columns) ->
          raise ArgumentError, "header columns must be a map"

        {:ok, columns} ->
          Map.new(columns, fn {key, patterns} ->
            {key, Enum.map(patterns, &normalise/1)}
          end)
      end

    required = Keyword.get(opts, :required)
    min_matches = Keyword.get(opts, :min_matches, map_size(columns))

    validate_min_matches(columns, min_matches)

    validate_required(columns, required)

    %__MODULE__{
      columns: columns,
      required: required,
      min_matches: min_matches
    }
  end

  defp validate_min_matches(columns, min_matches) do
    if min_matches > map_size(columns) do
      raise ArgumentError, "min_matches cannot be greater than the number of header columns"
    end
  end

  defp validate_required(columns, required) do
    Enum.each(required, fn req ->
      if not Map.has_key?(columns, req) do
        raise ArgumentError, "required column #{req} is not in header columns"
      end
    end)
  end

  @type positions :: %{String.t() => non_neg_integer()}

  @type miss :: %{matched: [String.t()], missing: [String.t()]}

  @spec matches(t(), [String.t()]) :: {:ok, positions()} | {:error, miss()}

  def matches(
        %__MODULE__{columns: columns, required: required, min_matches: min_matches},
        header
      ) do
    matched_columns = extract_matched_columns(columns, header)
    matched_keys = Map.keys(matched_columns)

    minimum_matches = length(matched_keys) >= min_matches
    all_required = Enum.all?(required, &(&1 in matched_keys))

    if minimum_matches and all_required do
      {:ok, matched_columns}
    else
      missing_required = Enum.filter(required, &(&1 not in matched_keys))

      {:error, %{matched: matched_keys, missing: missing_required}}
    end
  end

  defp extract_matched_columns(columns, header) do
    Enum.reduce(columns, %{}, fn {key, patterns}, acc ->
      case Enum.find_index(header, &cell_matches?(&1, patterns)) do
        nil -> acc
        idx -> Map.put(acc, key, idx)
      end
    end)
  end

  defp cell_matches?(col, patterns) when is_binary(col) do
    normalised_col = normalise(col)

    Enum.any?(patterns, &pattern_matches?(&1, col, normalised_col))
  end

  defp cell_matches?(_col, _patterns), do: false

  defp pattern_matches?(%Regex{} = pattern, col, _normalised_col), do: Regex.match?(pattern, col)

  defp pattern_matches?(pattern, _col, normalised_col), do: normalised_col == pattern
end
