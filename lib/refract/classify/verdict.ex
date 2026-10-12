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

  def first(winner, others), do: match(winner, nil, rank([winner | others]))

  defp rank(candidates), do: Enum.sort_by(candidates, &{status_rank(&1.status), -&1.score})

  defp status_rank(:matched), do: 0
  defp status_rank(:rows_failed), do: 1
  defp status_rank(:no_header), do: 2

  defp decide([], [top | _] = candidates, _margin) do
    %Result{verdict: :unknown, reason: top.status, shape: closest(top), candidates: candidates}
  end

  defp decide([only], candidates, _margin), do: match(only, nil, candidates)

  defp decide([%Candidate{score: top} = first, %Candidate{score: next} | _], candidates, margin)
       when top - next >= margin do
    match(first, nil, candidates)
  end

  defp decide([%Candidate{score: top} | _] = matched, candidates, margin) do
    matched
    |> Enum.take_while(&(top - &1.score < margin))
    |> most(&marker_hits/1)
    |> tie_break(candidates)
  end

  defp closest(%Candidate{header: nil}), do: nil

  defp closest(%Candidate{shape: shape} = candidate) do
    candidate
    |> matched_columns()
    |> closest_shape(shape)
  end

  defp closest_shape(0, _shape), do: nil
  defp closest_shape(_matched, shape), do: shape

  defp marker_hits(%Candidate{markers: markers}), do: Enum.count(markers, & &1.passed)

  defp matched_columns(%Candidate{header: header}), do: Header.matched_count(header)

  defp tie_break({hits, [winner]}, candidates) when hits > 0,
    do: match(winner, :markers, candidates)

  defp tie_break({_hits, tied}, candidates) do
    tied
    |> by_columns()
    |> column_break(candidates)
  end

  defp by_columns(tied) do
    tied
    |> Enum.uniq_by(& &1.header.row)
    |> by_columns(tied)
  end

  defp by_columns([_one_header], tied), do: most(tied, &matched_columns/1)
  defp by_columns(_headers, _tied), do: nil

  defp column_break({_columns, [winner]}, candidates),
    do: match(winner, :most_columns, candidates)

  defp column_break(_most_columns, candidates) do
    %Result{verdict: :ambiguous, reason: :within_margin, candidates: candidates}
  end

  defp most(tied, count) do
    tied
    |> Enum.group_by(count)
    |> Enum.max_by(fn {total, _candidates} -> total end)
  end

  defp match(%Candidate{shape: shape}, reason, candidates) do
    %Result{verdict: :match, reason: reason, shape: shape, candidates: candidates}
  end
end
