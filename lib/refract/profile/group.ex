defmodule Refract.Profile.Group do
  @moduledoc false

  alias Refract.Clean
  alias Refract.Profile.Cluster
  alias Refract.Profile.Variant

  import Refract.String.Utils, only: [text: 1]

  @type counted :: %{Refract.cell() => {non_neg_integer(), Variant.t()}}

  @spec clusters(counted()) :: {:done | :skipped, [Cluster.t()]}

  def clusters(values) do
    {fuzzy, joined} =
      values
      |> Map.values()
      |> Enum.group_by(fn {_order, %Variant{value: value}} -> normalised(value) end)
      |> join_fuzzy()

    {fuzzy,
     joined
     |> Enum.filter(fn {_key, members, _via} -> match?([_, _ | _], members) end)
     |> Enum.sort_by(fn {_key, members, _via} -> {-total(members), first_seen(members)} end)
     |> Enum.map(&cluster/1)}
  end

  defp join_fuzzy(groups) when map_size(groups) > 500,
    do: {:skipped, Enum.map(groups, fn {key, members} -> {key, members, :normalised} end)}

  defp join_fuzzy(groups) do
    {:done,
     groups
     |> Enum.sort_by(fn {_key, members} -> {-total(members), first_seen(members)} end)
     |> Enum.reduce([], &join/2)
     |> Enum.reverse()}
  end

  defp join({key, members}, anchors) do
    anchors
    |> Enum.find_index(fn {anchor, _members, _via} -> fuzzy?(anchor, key) end)
    |> join_at(key, members, anchors)
  end

  defp join_at(nil, key, members, anchors), do: [{key, members, :normalised} | anchors]

  defp join_at(index, _key, members, anchors) do
    List.update_at(anchors, index, fn {anchor, joined, _via} ->
      {anchor, joined ++ members, :fuzzy}
    end)
  end

  defp fuzzy?({anchor, digits}, {key, digits}), do: String.jaro_distance(anchor, key) >= 0.94
  defp fuzzy?(_anchor, _key), do: false

  defp total(ranked),
    do: ranked |> Enum.map(fn {_order, %Variant{count: count}} -> count end) |> Enum.sum()

  defp first_seen(ranked), do: ranked |> Enum.map(&elem(&1, 0)) |> Enum.min()

  defp cluster({_key, members, via}) do
    [{_order, %Variant{value: most_common}} | _] =
      ranked = Enum.sort_by(members, fn {order, %Variant{count: count}} -> {-count, order} end)

    %Cluster{
      most_common: most_common,
      via: via,
      variants: Enum.map(ranked, fn {_order, variant} -> in_order(variant) end)
    }
  end

  defp in_order(%Variant{lines: lines} = variant), do: %{variant | lines: Enum.reverse(lines)}

  defp normalised(value) do
    slug = value |> text() |> Clean.slug()

    {String.replace(slug, "_", ""), String.split(slug, ~r/[^0-9]+/, trim: true)}
  end
end
