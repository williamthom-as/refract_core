defmodule Refract.Classify.Score do
  @moduledoc false

  alias Refract.Classify.Result
  alias Refract.Shape

  @type opt ::
          {:within, non_neg_integer()}
          | {:min_score, number()}
          | {:margin, number()}
          | {:values, boolean()}

  @spec validate_opts!(keyword()) :: keyword()

  def validate_opts!(opts) do
    opts = Keyword.validate!(opts, within: 100, min_score: 0.5, margin: 0.1, values: false)

    validate_within(Keyword.fetch!(opts, :within))
    validate_fraction(Keyword.fetch!(opts, :min_score), :min_score)
    validate_fraction(Keyword.fetch!(opts, :margin), :margin)
    validate_values(Keyword.fetch!(opts, :values))

    opts
  end

  @spec run(Enumerable.t(), [Shape.t() | module()], [opt()]) :: Result.t()

  def run(raw, shapes, opts) do
    opts = validate_opts!(opts)

    within = Keyword.fetch!(opts, :within)
    min_score = Keyword.fetch!(opts, :min_score)
    margin = Keyword.fetch!(opts, :margin)
    values = Keyword.fetch!(opts, :values)

    resolved_shapes = resolve_shapes(shapes)
    sample = Enum.take(raw, within)
  end

  defp resolve_shapes(shapes) when is_list(shapes) and shapes != [] do
    Enum.map(shapes, &Shape.resolve/1)
  end

  defp resolve_shapes(shapes) do
    raise ArgumentError, "shapes must be a list of at least one shape, got: #{inspect(shapes)}"
  end

  defp validate_within(within) when is_integer(within) and within >= 0, do: :ok

  defp validate_within(within) do
    raise ArgumentError, "within must be a non negative integer, got: #{inspect(within)}"
  end

  defp validate_fraction(value, _name) when is_number(value) and value >= 0 and value <= 1,
    do: :ok

  defp validate_fraction(value, name) do
    raise ArgumentError, "#{name} must be a number from 0 to 1, got: #{inspect(value)}"
  end

  defp validate_values(values) when is_boolean(values), do: :ok

  defp validate_values(values) do
    raise ArgumentError, "values must be true or false, got: #{inspect(values)}"
  end
end
