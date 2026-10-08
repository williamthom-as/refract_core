defmodule Refract.Table.Report.Rule do
  @moduledoc false

  alias Refract.Table.Spec.Stop

  defstruct [:rule, :passed, :expected, :actual, :missing]

  @type t :: %__MODULE__{
          rule: :min_matches | :required | :min_score | Stop.condition(),
          passed: boolean(),
          expected: number() | [String.t()] | nil,
          actual: number() | nil,
          missing: [String.t()] | nil
        }

  @spec for_min_matches(boolean(), non_neg_integer(), non_neg_integer()) :: t()

  def for_min_matches(passed, expected, actual) do
    %__MODULE__{rule: :min_matches, passed: passed, expected: expected, actual: actual}
  end

  @spec for_required(boolean(), [String.t()], [String.t()]) :: t()

  def for_required(passed, expected, missing) do
    %__MODULE__{rule: :required, passed: passed, expected: expected, missing: missing}
  end

  @spec for_min_score(boolean(), number(), number()) :: t()

  def for_min_score(passed, expected, actual) do
    %__MODULE__{rule: :min_score, passed: passed, expected: expected, actual: actual}
  end

  @spec for_stop(Stop.condition(), boolean()) :: t()

  def for_stop(condition, passed) do
    %__MODULE__{rule: condition, passed: passed}
  end
end
