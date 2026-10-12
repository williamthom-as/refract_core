defmodule Refract.Classify.Markers do
  @moduledoc false

  alias Refract.Classify.Candidate
  alias Refract.Classify.Ctx
  alias Refract.Classify.Marker
  alias Refract.Shape

  import Refract.String.Utils, only: [blank?: 1]

  @spec add(Candidate.t(), Ctx.t()) :: Candidate.t()

  def add(%Candidate{shape: %Shape{markers: markers}} = candidate, %Ctx{} = ctx) do
    %{candidate | markers: Enum.map(markers, &marker(&1, ctx))}
  end

  defp marker({:file, pattern}, %Ctx{name: name}) do
    %Marker{marker: :file, pattern: pattern, against: name, passed: file_hit?(pattern, name)}
  end

  defp marker({:content, pattern}, %Ctx{sample: sample}) do
    against = Enum.find_value(sample, &content_hit(&1, pattern))

    %Marker{marker: :content, pattern: pattern, against: against, passed: against != nil}
  end

  defp file_hit?(_pattern, nil), do: false

  defp file_hit?(pattern, name), do: Regex.match?(pattern, name)

  defp content_hit(line, pattern), do: Enum.find(line, &content_cell?(&1, pattern))

  defp content_cell?(cell, pattern) when is_binary(cell),
    do: not blank?(cell) and Regex.match?(pattern, cell)

  defp content_cell?(_cell, _pattern), do: false
end
