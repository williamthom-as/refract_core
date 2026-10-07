defmodule Refract.Shape.Load do
  @moduledoc false

  @compile {:no_warn_undefined, YamlElixir}

  alias Refract.Shape

  @spec run(Path.t()) :: {:ok, Shape.t()} | {:error, Shape.load_error()}

  def run(path) do
    with {:ok, map} <- open_yaml_file(path) do
      Shape.from_map(map)
    end
  end

  defp open_yaml_file(path) do
    if Code.ensure_loaded?(YamlElixir) do
      with {:ok, content} <- read_file(path) do
        read_yaml(content)
      end
    else
      {:error, {:missing_dependency, :yaml_elixir}}
    end
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, {:file_read_error, reason}}
    end
  end

  defp read_yaml(content) do
    case YamlElixir.read_from_string(content) do
      {:ok, map} -> {:ok, map}
      {:error, exception} -> {:error, {:invalid_yaml, Exception.message(exception)}}
    end
  end
end
