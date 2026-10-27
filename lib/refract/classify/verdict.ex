defmodule Refract.Classify.Verdict do
  @moduledoc false

  alias Refract.Classify.Candidate
  alias Refract.Classify.Result
  alias Refract.Table.Spec.Header

  @spec best([Candidate.t()], number(), number()) :: Result.t()

  def best(candidates, margin, min_score) do
    ranked = rank(candidates)
    matched = Enum.filter(ranked, &match?(%Candidate{status: :matched}, &1))
    {narrower, kept} = Enum.split_with(matched, &narrower?(&1, matched))

    kept
    |> decide(ranked, margin, min_score)
    |> wider_header(narrower, margin)
  end

  @spec first(Candidate.t(), [Candidate.t()]) :: Result.t()

  def first(winner, others), do: match(winner, nil, rank([winner | others]))

  defp rank(candidates), do: Enum.sort_by(candidates, &{status_rank(&1.status), -&1.score})

  defp status_rank(:matched), do: 0
  defp status_rank(:rows_failed), do: 1
  defp status_rank(:no_header), do: 2

  defp decide([], [top | _] = candidates, _margin, min_score) do
    %Result{
      verdict: :unknown,
      reason: top.status,
      shape: closest(top, min_score),
      candidates: candidates
    }
  end

  defp decide([only], candidates, _margin, _min_score), do: match(only, nil, candidates)

  defp decide(
         [%Candidate{score: top} = first, %Candidate{score: next} | _],
         candidates,
         margin,
         _min_score
       )
       when top - next >= margin do
    match(first, nil, candidates)
  end

  defp decide([%Candidate{score: top} | _] = matched, candidates, margin, _min_score) do
    matched
    |> Enum.take_while(&(top - &1.score < margin))
    |> most(&marker_hits/1)
    |> tie_break(candidates)
  end

  defp closest(%Candidate{header: nil}, _min_score), do: nil
  defp closest(%Candidate{status: :rows_failed, shape: shape}, _min_score), do: shape

  defp closest(%Candidate{score: score, shape: shape}, min_score)
       when score > 0 and score >= min_score,
       do: shape

  defp closest(_candidate, _min_score), do: nil

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

  defp narrower?(candidate, matched), do: Enum.any?(matched, &wider?(&1, candidate))

  defp wider?(%Candidate{header: %{row: row}} = wide, %Candidate{header: %{row: row}} = narrow) do
    narrow_cells = cells(narrow)
    wide_cells = cells(wide)

    marker_hits(wide) >= marker_hits(narrow) and MapSet.subset?(narrow_cells, wide_cells) and
      narrow_cells != wide_cells
  end

  defp wider?(_wide, _narrow), do: false

  defp cells(%Candidate{header: header}) do
    header
    |> Header.positions()
    |> Map.values()
    |> MapSet.new()
  end

  defp wider_header(
         %Result{verdict: :match, reason: nil, shape: shape} = result,
         narrower,
         margin
       ) do
    %Candidate{score: score} = Enum.find(result.candidates, &(&1.shape == shape))

    if Enum.any?(narrower, &(score - &1.score < margin)) do
      %{result | reason: :wider_header}
    else
      result
    end
  end

  defp wider_header(result, _narrower, _margin), do: result

  defp most(tied, count) do
    tied
    |> Enum.group_by(count)
    |> Enum.max_by(fn {total, _candidates} -> total end)
  end

  defp match(%Candidate{shape: shape}, reason, candidates) do
    %Result{verdict: :match, reason: reason, shape: shape, candidates: candidates}
  end
end
