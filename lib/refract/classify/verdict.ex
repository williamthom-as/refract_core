defmodule Refract.Classify.Verdict do
  @moduledoc false

  alias Refract.Classify.Candidate
  alias Refract.Classify.Result
  alias Refract.Table.Spec.Header

  @spec best([Candidate.t()], number()) :: Result.t()

  def best(candidates, margin) do
    ranked = rank(candidates)

    ranked
    |> Enum.filter(&match?(%Candidate{status: :matched}, &1))
    |> decide(ranked, margin)
  end

  @spec first(Candidate.t(), [Candidate.t()]) :: Result.t()

  def first(%Candidate{shape: shape} = winner, others) do
    %Result{verdict: :match, shape: shape, candidates: rank([winner | others])}
  end

  defp rank(candidates), do: Enum.sort_by(candidates, &{status_rank(&1.status), -&1.score})

  defp status_rank(:matched), do: 0
  defp status_rank(:rows_failed), do: 1
  defp status_rank(:no_header), do: 2

  defp decide([], [top | _] = candidates, _margin) do
    %Result{verdict: :unknown, reason: top.status, shape: closest(top), candidates: candidates}
  end

  defp decide([top], candidates, _margin) do
    %Result{verdict: :match, shape: top.shape, candidates: candidates}
  end

  defp decide([first, second | _], candidates, margin) do
    if first.score - second.score < margin do
      %Result{verdict: :ambiguous, reason: :within_margin, candidates: candidates}
    else
      %Result{verdict: :match, shape: first.shape, candidates: candidates}
    end
  end

  defp closest(%Candidate{header: nil}), do: nil

  defp closest(%Candidate{shape: shape, header: header}) do
    header
    |> Header.positions()
    |> map_size()
    |> closest_shape(shape)
  end

  defp closest_shape(0, _shape), do: nil
  defp closest_shape(_matched, shape), do: shape
end
