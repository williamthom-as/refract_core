defmodule Refract.Shape.FromMap do
  @moduledoc false

  import Refract.String.Utils, only: [blank?: 1]

  alias Refract.Shape
  alias Refract.Table

  @keys ~w(name version markers header row stop max_misses)
  @header_keys ~w(columns required min_matches)
  @row_keys ~w(match min_score)
  @marker_keys ~w(file content)

  @spec run(term()) :: {:ok, Shape.t()} | {:error, Shape.error()}

  def run(map) when not is_map(map), do: {:error, {:not_a_map, map}}

  def run(map) do
    map = present(map)

    with :ok <- known_keys(map, @keys, nil),
         {:ok, name} <- name(map),
         {:ok, version} <- version(Map.get(map, "version", 1)),
         {:ok, markers} <- markers(Map.get(map, "markers", %{})),
         {:ok, spec} <- spec(map) do
      {:ok, Shape.new(name: name, version: version, spec: spec, markers: markers)}
    end
  end

  defp name(%{"name" => name}) when is_binary(name) do
    if blank?(name) do
      invalid("name", name)
    else
      {:ok, name}
    end
  end

  defp name(%{"name" => name}), do: invalid("name", name)
  defp name(_map), do: {:error, {:missing_key, "name"}}

  defp version(version) when is_integer(version) and version > 0, do: {:ok, version}
  defp version(version), do: invalid("version", version)

  defp markers(markers) when is_map(markers) do
    markers = present(markers)

    with :ok <- known_keys(markers, @marker_keys, "markers") do
      markers(@marker_keys, markers, [])
    end
  end

  defp markers(markers), do: invalid("markers", markers)

  defp markers([], _markers, parsed), do: {:ok, Enum.reverse(parsed)}

  defp markers([key | rest], markers, parsed) when is_map_key(markers, key) do
    case regex_only("markers." <> key, Map.fetch!(markers, key)) do
      {:ok, regex} -> markers(rest, markers, [{marker_key(key), regex} | parsed])
      error -> error
    end
  end

  defp markers([_key | rest], markers, parsed), do: markers(rest, markers, parsed)

  defp marker_key("file"), do: :file
  defp marker_key("content"), do: :content

  defp spec(map) do
    with {:ok, header} <- header(Map.get(map, "header")),
         {:ok, row} <- row(Map.get(map, "row", %{})),
         {:ok, stop} <- stop(Map.get(map, "stop", []), []) do
      build_spec(
        [header: header, row: row, stop: stop] ++ take_opts(map, max_misses: "max_misses")
      )
    end
  end

  defp build_spec(opts) do
    {:ok, Table.spec(opts)}
  rescue
    error in ArgumentError -> {:error, {:invalid_spec, Exception.message(error)}}
  end

  defp header(nil), do: {:error, {:missing_key, "header"}}

  defp header(header) when is_map(header) do
    header = present(header)

    with :ok <- known_keys(header, @header_keys, "header"),
         {:ok, columns} <- columns(Map.get(header, "columns")),
         :ok <- validate_required(Map.get(header, "required", [])) do
      {:ok,
       [columns: columns] ++ take_opts(header, required: "required", min_matches: "min_matches")}
    end
  end

  defp header(header), do: invalid("header", header)

  defp columns(nil), do: {:error, {:missing_key, "header.columns"}}
  defp columns(columns) when is_map(columns), do: columns(Map.to_list(columns), %{})
  defp columns(columns), do: invalid("header.columns", columns)

  defp columns([], parsed), do: {:ok, parsed}

  defp columns([{name, aliases} | rest], parsed) when is_binary(name) do
    case aliases("header.columns." <> name, aliases) do
      {:ok, aliases} -> columns(rest, Map.put(parsed, name, aliases))
      error -> error
    end
  end

  defp columns([{name, _aliases} | _rest], _parsed), do: invalid("header.columns", name)

  defp aliases(path, aliases) when is_binary(aliases), do: aliases(path, [aliases], [])
  defp aliases(path, aliases) when is_list(aliases), do: aliases(path, aliases, [])
  defp aliases(path, aliases), do: invalid(path, aliases)

  defp aliases(_path, [], parsed), do: {:ok, Enum.reverse(parsed)}

  defp aliases(path, [value | rest], parsed) when is_binary(value) do
    case to_regex(value) do
      :plain -> aliases(path, rest, [value | parsed])
      {:ok, regex} -> aliases(path, rest, [regex | parsed])
      {:error, _reason} -> invalid(path, value)
    end
  end

  defp aliases(path, [value | _rest], _parsed), do: invalid(path, value)

  defp validate_required(required) when is_list(required) do
    if Enum.all?(required, &is_binary/1) do
      :ok
    else
      invalid("header.required", required)
    end
  end

  defp validate_required(required), do: invalid("header.required", required)

  defp row(row) when is_map(row) do
    row = present(row)

    with :ok <- known_keys(row, @row_keys, "row"),
         {:ok, match} <- rules(Map.get(row, "match", %{})) do
      {:ok, [match: match] ++ take_opts(row, min_score: "min_score")}
    end
  end

  defp row(row), do: invalid("row", row)

  defp rules(rules) when is_map(rules), do: rules(Map.to_list(rules), %{})
  defp rules(rules), do: invalid("row.match", rules)

  defp rules([], parsed), do: {:ok, parsed}

  defp rules([{column, rule} | rest], parsed) do
    case rule("row.match.#{column}", rule) do
      {:ok, rule} -> rules(rest, Map.put(parsed, column, rule))
      error -> error
    end
  end

  defp rule(_path, "integer"), do: {:ok, :integer}
  defp rule(_path, "number"), do: {:ok, :number}
  defp rule(_path, "date"), do: {:ok, :date}
  defp rule(_path, "datetime"), do: {:ok, :datetime}
  defp rule(path, value), do: regex_only(path, value)

  defp stop([], parsed), do: {:ok, Enum.reverse(parsed)}
  defp stop(["blank" | rest], parsed), do: stop(rest, [:blank | parsed])

  defp stop([%{"contains" => value} = condition | rest], parsed) when map_size(condition) == 1 do
    case regex_only("stop.contains", value) do
      {:ok, regex} -> stop(rest, [{:contains, regex} | parsed])
      error -> error
    end
  end

  defp stop([condition | _rest], _parsed), do: invalid("stop", condition)
  defp stop(conditions, _parsed), do: invalid("stop", conditions)

  defp regex_only(path, value) when is_binary(value) do
    case to_regex(value) do
      {:ok, regex} -> {:ok, regex}
      _plain_or_error -> invalid(path, value)
    end
  end

  defp regex_only(path, value), do: invalid(path, value)

  defp to_regex("/" <> rest) do
    case rest |> String.reverse() |> String.split("/", parts: 2) do
      [flags, source] -> Regex.compile(String.reverse(source), String.reverse(flags))
      [_unclosed] -> {:error, :unclosed}
    end
  end

  defp to_regex(_value), do: :plain

  defp present(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)

  defp take_opts(map, keys) do
    for {opt, key} <- keys, Map.has_key?(map, key), do: {opt, Map.fetch!(map, key)}
  end

  defp known_keys(map, allowed, prefix) do
    case Enum.find(Map.keys(map), &(&1 not in allowed)) do
      nil -> :ok
      key -> {:error, {:unknown_key, key_path(prefix, key)}}
    end
  end

  defp key_path(nil, key), do: "#{key}"
  defp key_path(prefix, key), do: "#{prefix}.#{key}"

  defp invalid(path, value), do: {:error, {:invalid_value, {path, value}}}
end
