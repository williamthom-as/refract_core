defmodule Refract.Shape.FromMap do
  @moduledoc false

  import Refract.String.Utils, only: [blank?: 1]

  alias Refract.Parse.Date, as: DateParser
  alias Refract.Shape
  alias Refract.Table
  alias Refract.Validate.Validator

  @keys ~w(name version markers header row stop max_misses validation fields)
  @header_keys ~w(columns required min_matches ignore)
  @row_keys ~w(match min_score)
  @marker_keys ~w(file content)
  @validation_keys ~w(columns unique)
  @field_keys ~w(label take at rules)
  @rule_names ~w(required unique integer number date datetime min max in)
  @date_formats ~w(iso ymd dmy mdy)

  @spec run(term(), [Shape.from_map_opt()]) :: {:ok, Shape.t()} | {:error, Shape.error()}

  def run(map, opts) do
    opts = Keyword.validate!(opts, validators: %{})

    validators = Keyword.fetch!(opts, :validators)

    validate_validators(validators)

    shape(map, validators)
  end

  defp validate_validators(validators) when is_map(validators),
    do: Enum.each(validators, &validate_validator/1)

  defp validate_validators(validators) do
    raise ArgumentError,
          "validators must be a map of names to validator modules, got: #{inspect(validators)}"
  end

  defp validate_validator({name, _module}) when name in @rule_names do
    raise ArgumentError, "validators name #{inspect(name)} is a built in rule"
  end

  defp validate_validator({name, module}) when is_binary(name),
    do: validate_module(Validator.validator?(module), name, module)

  defp validate_validator({name, _module}) do
    raise ArgumentError, "validators names must be strings, got: #{inspect(name)}"
  end

  defp validate_module(true, _name, _module), do: :ok

  defp validate_module(false, name, module) do
    raise ArgumentError,
          "validators #{inspect(name)} must implement Refract.Validate.Validator, " <>
            "got: #{inspect(module)}"
  end

  defp shape(map, _validators) when not is_map(map), do: {:error, {:not_a_map, map}}

  defp shape(map, validators) do
    map = present(map)

    with :ok <- known_keys(map, @keys, nil),
         {:ok, name} <- name(map),
         {:ok, version} <- version(Map.get(map, "version", 1)),
         {:ok, markers} <- markers(Map.get(map, "markers", %{})),
         {:ok, spec} <- spec(map),
         {:ok, validation} <- validation(Map.get(map, "validation", %{}), validators),
         {:ok, fields} <- fields(Map.get(map, "fields", %{}), validators) do
      build_shape(
        name: name,
        version: version,
        spec: spec,
        markers: markers,
        validation: validation,
        fields: fields
      )
    end
  end

  defp build_shape(opts) do
    {:ok, Shape.new(opts)}
  rescue
    error in ArgumentError -> {:error, {:invalid_shape, Exception.message(error)}}
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

  defp date_formats(formats) when is_list(formats) do
    formats = Enum.map(formats, &date_format/1)

    DateParser.validate_formats!(formats)

    {:ok, formats}
  rescue
    ArgumentError -> :error
  end

  defp date_formats(_formats), do: :error

  defp date_format(name) when name in @date_formats, do: String.to_existing_atom(name)
  defp date_format(pattern), do: pattern

  defp dated(path, kind, formats, rule) do
    case date_formats(formats) do
      {:ok, formats} -> {:ok, {kind, formats}}
      :error -> invalid(path, rule)
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
         :ok <- validate_required(Map.get(header, "required", [])),
         {:ok, ignore} <- aliases("header.ignore", Map.get(header, "ignore", [])) do
      {:ok,
       [columns: columns, ignore: ignore] ++
         take_opts(header, required: "required", min_matches: "min_matches")}
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

  defp rule(path, %{"date" => formats} = rule) when map_size(rule) == 1,
    do: dated(path, :date, formats, rule)

  defp rule(path, %{"datetime" => formats} = rule) when map_size(rule) == 1,
    do: dated(path, :datetime, formats, rule)

  defp rule(_path, "date"), do: {:ok, :date}
  defp rule(_path, "datetime"), do: {:ok, :datetime}
  defp rule(path, value), do: regex_only(path, value)

  defp fields(fields, validators) when is_map(fields),
    do: fields(Map.to_list(fields), validators, %{})

  defp fields(fields, _validators), do: invalid("fields", fields)

  defp fields([], _validators, parsed), do: {:ok, parsed}

  defp fields([{name, field} | rest], validators, parsed)
       when is_binary(name) and is_map(field) do
    case field("fields." <> name, present(field), validators) do
      {:ok, opts} -> fields(rest, validators, Map.put(parsed, name, opts))
      error -> error
    end
  end

  defp fields([{name, field} | _rest], _validators, _parsed),
    do: invalid("fields.#{name}", field)

  defp field(path, field, validators) do
    with :ok <- known_keys(field, @field_keys, path),
         {:ok, rules} <- field_rules(path <> ".rules", Map.get(field, "rules", []), validators),
         {:ok, find} <- field_find(path, field) do
      {:ok, [rules: rules] ++ find}
    end
  end

  defp field_rules(path, rules, validators) when is_list(rules),
    do: validation_rules(path, rules, validators, [])

  defp field_rules(path, rules, _validators), do: invalid(path, rules)

  defp field_find(path, field) do
    with {:ok, label} <- field_label(path <> ".label", Map.get(field, "label")),
         {:ok, take} <- field_take(path <> ".take", Map.get(field, "take", "right")) do
      {:ok, label ++ take ++ take_opts(field, at: "at")}
    end
  end

  defp field_label(_path, nil), do: {:ok, []}

  defp field_label(path, label) when is_binary(label) do
    case to_regex(label) do
      :plain -> {:ok, [label: label]}
      {:ok, regex} -> {:ok, [label: regex]}
      {:error, _reason} -> invalid(path, label)
    end
  end

  defp field_label(path, label), do: invalid(path, label)

  defp field_take(_path, "right"), do: {:ok, [take: :right]}
  defp field_take(_path, "below"), do: {:ok, [take: :below]}
  defp field_take(path, take), do: invalid(path, take)

  defp validation(validation, validators) when is_map(validation) do
    validation = present(validation)

    with :ok <- known_keys(validation, @validation_keys, "validation"),
         {:ok, columns} <- validation_columns(Map.get(validation, "columns", %{}), validators),
         {:ok, unique} <- validation_unique(Map.get(validation, "unique", [])) do
      {:ok, [columns: columns, unique: unique]}
    end
  end

  defp validation(validation, _validators), do: invalid("validation", validation)

  defp validation_unique(unique) when is_list(unique),
    do: unique |> Enum.all?(&combination?/1) |> validation_unique(unique)

  defp validation_unique(unique), do: invalid("validation.unique", unique)

  defp validation_unique(true, unique), do: {:ok, unique}
  defp validation_unique(false, unique), do: invalid("validation.unique", unique)

  defp combination?(columns) when is_list(columns), do: Enum.all?(columns, &is_binary/1)
  defp combination?(_columns), do: false

  defp validation_columns(columns, validators) when is_map(columns),
    do: validation_columns(Map.to_list(columns), validators, %{})

  defp validation_columns(columns, _validators), do: invalid("validation.columns", columns)

  defp validation_columns([], _validators, parsed), do: {:ok, parsed}

  defp validation_columns([{column, rules} | rest], validators, parsed) when is_list(rules) do
    case validation_rules("validation.columns.#{column}", rules, validators, []) do
      {:ok, rules} -> validation_columns(rest, validators, Map.put(parsed, column, rules))
      error -> error
    end
  end

  defp validation_columns([{column, rules} | _rest], _validators, _parsed),
    do: invalid("validation.columns.#{column}", rules)

  defp validation_rules(_path, [], _validators, parsed), do: {:ok, Enum.reverse(parsed)}

  defp validation_rules(path, [rule | rest], validators, parsed) do
    case validation_rule(path, rule, validators) do
      {:ok, rule} -> validation_rules(path, rest, validators, [rule | parsed])
      error -> error
    end
  end

  defp validation_rule(_path, "required", _validators), do: {:ok, :required}
  defp validation_rule(_path, "unique", _validators), do: {:ok, :unique}

  defp validation_rule(_path, name, validators) when is_map_key(validators, name),
    do: {:ok, Map.fetch!(validators, name)}

  defp validation_rule(path, %{"min" => bound} = rule, _validators) when map_size(rule) == 1,
    do: bound(path, :min, bound)

  defp validation_rule(path, %{"max" => bound} = rule, _validators) when map_size(rule) == 1,
    do: bound(path, :max, bound)

  defp validation_rule(_path, %{"in" => values} = rule, _validators)
       when map_size(rule) == 1 and is_list(values),
       do: {:ok, {:in, values}}

  defp validation_rule(path, rule, validators) when is_map(rule) and map_size(rule) == 1 do
    [{name, options}] = Map.to_list(rule)
    validator(path, rule, Map.fetch(validators, name), options)
  end

  defp validation_rule(path, rule, _validators), do: rule(path, rule)

  defp validator(path, rule, {:ok, module}, options) when is_map(options) do
    case validator_opts(Map.to_list(options), []) do
      {:ok, opts} -> {:ok, {module, opts}}
      :error -> invalid(path, rule)
    end
  end

  defp validator(path, rule, :error, _options), do: rule(path, rule)
  defp validator(path, rule, {:ok, _module}, _options), do: invalid(path, rule)

  defp validator_opts([], parsed), do: {:ok, Enum.reverse(parsed)}

  defp validator_opts([{name, value} | rest], parsed) when is_binary(name) do
    case existing_atom(name) do
      {:ok, name} -> validator_opts(rest, [{name, value} | parsed])
      :error -> :error
    end
  end

  defp validator_opts(_options, _parsed), do: :error

  defp existing_atom(name) do
    {:ok, String.to_existing_atom(name)}
  rescue
    ArgumentError -> :error
  end

  defp bound(_path, side, bound) when is_number(bound), do: {:ok, {side, bound}}

  defp bound(path, side, bound) when is_binary(bound) do
    case Date.from_iso8601(bound) do
      {:ok, date} -> {:ok, {side, date}}
      {:error, _reason} -> invalid(path, %{Atom.to_string(side) => bound})
    end
  end

  defp bound(path, side, bound), do: invalid(path, %{Atom.to_string(side) => bound})

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
