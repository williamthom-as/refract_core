defmodule Refract.Table.Spec.Row do
  import Refract.Utils, only: [truthy?: 1]

  alias Refract.Parse

  defstruct [:match, :min_score]

  @type rule :: :integer | :number | :date | Regex.t() | (Refract.cell() -> as_boolean(term()))

  @type rules :: %{String.t() => rule()}

  @type t :: %__MODULE__{
          match: rules(),
          min_score: number()
        }

  def new(opts) do
    opts = Keyword.validate!(opts, [:match, :min_score])

    match = Keyword.get(opts, :match, %{})
    min_score = Keyword.get(opts, :min_score, 1.0)

    validate_min_score(min_score)
    validate_rules(match)

    %__MODULE__{
      match: match,
      min_score: min_score
    }
  end

  defp validate_rules(rules) when is_map(rules) do
    Enum.each(rules, fn {column, rule} ->
      if not is_binary(column) do
        raise ArgumentError, "column names must be strings"
      end

      if not valid_rule?(rule) do
        raise ArgumentError, "invalid rule for column #{column}: #{inspect(rule)}"
      end
    end)
  end

  defp validate_rules(_), do: raise(ArgumentError, "match rules must be a map")

  defp valid_rule?(rule) when rule in [:integer, :number, :date], do: true
  defp valid_rule?(%Regex{}), do: true
  defp valid_rule?(fun) when is_function(fun, 1), do: true
  defp valid_rule?(_), do: false

  defp validate_min_score(min_score)
       when is_number(min_score) and min_score >= 0 and min_score <= 1,
       do: :ok

  defp validate_min_score(_),
    do: raise(ArgumentError, "min_score must be a number between 0 and 1")

  @type miss :: %{score: float(), failed: [{String.t(), rule()}]}

  @spec matches(t(), Refract.row()) :: :ok | {:error, miss()}

  def matches(%__MODULE__{match: match}, _row) when map_size(match) == 0 do
    :ok
  end

  def matches(%__MODULE__{match: rules, min_score: min_score}, row) do
    {passed_count, failed} =
      Enum.reduce(rules, {0, []}, fn {column, rule}, {passed_count, failed} ->
        value = Map.get(row, column)

        if passes?(rule, value) do
          {passed_count + 1, failed}
        else
          {passed_count, [{column, rule} | failed]}
        end
      end)

    score = passed_count / map_size(rules)

    if score >= min_score do
      :ok
    else
      {:error, %{score: score, failed: failed}}
    end
  end

  defp passes?(_, nil), do: false

  defp passes?(:integer, value), do: match?({:ok, _}, Parse.integer(value))

  defp passes?(:number, value), do: match?({:ok, _}, Parse.number(value))

  defp passes?(:date, value), do: match?({:ok, _}, Parse.date(value))

  defp passes?(%Regex{} = regex, value) when is_binary(value) do
    Regex.match?(regex, value)
  end

  defp passes?(fun, value) when is_function(fun, 1) do
    truthy?(fun.(value))
  end

  defp passes?(_, _), do: false
end
