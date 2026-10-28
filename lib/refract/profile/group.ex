defmodule Refract.Profile.Group do
  @moduledoc false

  alias Refract.Clean
  alias Refract.Profile.Cluster
  alias Refract.Profile.Variant

  import Refract.String.Utils, only: [text: 1]

  @type counted :: %{Refract.cell() => {non_neg_integer(), Variant.t()}}

  @spec clusters(counted()) :: [Cluster.t()]

  def clusters(values) do
    values
    |> Map.values()
    |> Enum.group_by(fn {_order, %Variant{value: value}} -> fingerprint(value) end)
    |> Map.values()
    |> Enum.filter(&match?([_, _ | _], &1))
    |> Enum.map(&Enum.sort_by(&1, fn {order, %Variant{count: count}} -> {-count, order} end))
    |> Enum.sort_by(&{-total(&1), first_seen(&1)})
    |> Enum.map(&cluster/1)
  end

  defp total(ranked),
    do: ranked |> Enum.map(fn {_order, %Variant{count: count}} -> count end) |> Enum.sum()

  defp first_seen(ranked), do: ranked |> Enum.map(&elem(&1, 0)) |> Enum.min()

  defp cluster([{_order, %Variant{value: most_common}} | _] = ranked) do
    %Cluster{
      most_common: most_common,
      via: :fingerprint,
      variants: Enum.map(ranked, fn {_order, variant} -> in_order(variant) end)
    }
  end

  defp in_order(%Variant{lines: lines} = variant), do: %{variant | lines: Enum.reverse(lines)}

  defp fingerprint(value) do
    slug = value |> text() |> Clean.slug()

    {String.replace(slug, "_", ""), String.split(slug, ~r/[^0-9]+/, trim: true)}
  end
end
