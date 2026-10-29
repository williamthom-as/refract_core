defmodule Refract.Profile.Report do
  @moduledoc false

  alias Refract.Profile.Cluster
  alias Refract.Profile.Column
  alias Refract.Profile.Folders
  alias Refract.Profile.Result
  alias Refract.Profile.Variant
  alias Refract.Shape

  import Refract.String.Utils, only: [text: 1]

  @spec header() :: [String.t()]

  def header, do: ~w(shape version column most_common via variant count file lines)

  @spec header(:values) :: [String.t()]

  def header(:values), do: ~w(shape version column value count file lines)

  @spec rows(Result.t() | Folders.t(), :values) :: [%{String.t() => term()}]

  def rows(%Folders{results: results}, :values) do
    results
    |> Enum.sort_by(fn {key, _result} -> key end)
    |> Enum.flat_map(fn {_key, result} -> rows(result, :values) end)
  end

  def rows(%Result{shape: %Shape{name: name, version: version}, columns: columns}, :values) do
    for {column, %Column{values: [_ | _] = values}} <- Enum.sort(columns),
        %Variant{value: value, count: count} = variant <- values,
        {file, lines} <- places(variant) do
      %{
        "shape" => name,
        "version" => version,
        "column" => column,
        "value" => shown(value),
        "count" => count,
        "file" => file,
        "lines" => Enum.join(lines, ", ")
      }
    end
  end

  @spec rows(Result.t() | Folders.t()) :: [%{String.t() => term()}]

  def rows(%Folders{results: results}) do
    results
    |> Enum.sort_by(fn {key, _result} -> key end)
    |> Enum.flat_map(fn {_key, result} -> rows(result) end)
  end

  def rows(%Result{shape: %Shape{name: name, version: version}, columns: columns}) do
    for {column, %Column{clusters: clusters}} <- Enum.sort(columns),
        %Cluster{most_common: most_common, via: via, variants: variants} <- clusters,
        %Variant{value: value, count: count} = variant <- variants,
        {file, lines} <- places(variant) do
      %{
        "shape" => name,
        "version" => version,
        "column" => column,
        "most_common" => shown(most_common),
        "via" => via,
        "variant" => shown(value),
        "count" => count,
        "file" => file,
        "lines" => Enum.join(lines, ", ")
      }
    end
  end

  defp places(%Variant{files: nil, lines: lines}), do: [{nil, lines}]
  defp places(%Variant{files: files}), do: Enum.sort(files)

  defp shown(value), do: value |> text() |> shown_text()

  defp shown_text(text),
    do: shown_text(Regex.match?(~r/^\s|\s$|[^\S ]|[\p{Cc}\p{Cf}]/u, text), text)

  defp shown_text(true, text), do: inspect(text)
  defp shown_text(false, text), do: text
end
