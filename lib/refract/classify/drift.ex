defmodule Refract.Classify.Drift do
  @moduledoc false

  alias Refract.Classify.Candidate
  alias Refract.Classify.Result
  alias Refract.Table.Report

  defstruct missing: [], extra: [], others: %{}

  @type cells :: [{non_neg_integer(), Refract.cell()}]

  @type t :: %__MODULE__{
          missing: [String.t()],
          extra: cells(),
          others: %{String.t() => cells()}
        }

  @spec from(Result.t()) :: t() | nil

  def from(%Result{shape: nil}), do: nil

  def from(%Result{shape: shape, candidates: candidates}) do
    %Candidate{header: %Report.Line{columns: columns, extra: extra}} =
      Enum.find(candidates, &(&1.shape == shape))

    missing = for {column, %Report.Column{passed: false}} <- columns, do: column

    others =
      for {column, %Report.Column{others: [_ | _] = others}} <- columns,
          into: %{},
          do: {column, others}

    %__MODULE__{missing: Enum.sort(missing), extra: extra, others: others}
  end
end
