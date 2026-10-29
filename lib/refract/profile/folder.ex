defmodule Refract.Profile.Folder do
  @moduledoc false

  alias Refract.Classify
  alias Refract.Profile.Count
  alias Refract.Profile.Ctx
  alias Refract.Profile.Folders
  alias Refract.Profile.Result
  alias Refract.Reader
  alias Refract.Shape

  @type opt :: Classify.Folder.opt() | Count.opt()

  @spec run(Path.t(), [Shape.t() | module()], [opt()]) :: {:ok, Folders.t()} | {:error, term()}

  def run(dir, shapes, opts) do
    {profile_opts, folder_opts} = Keyword.split(opts, Keyword.keys(Count.options()))

    resolved_shapes = Shape.resolve_all(shapes)
    {fuzzy, profile_opts} = shape_fuzzy(profile_opts)

    ctx =
      Count.ctx!(profile_opts ++ Keyword.take(folder_opts, [:within]), columns(resolved_shapes))

    validate_shape_fuzzy(fuzzy, resolved_shapes)

    with {:ok, classified} <- Classify.folder(dir, resolved_shapes, folder_opts) do
      {matched, unmatched} =
        classified
        |> Enum.map(&outcome/1)
        |> Enum.split_with(&match?({:match, _shape, _path, _reader}, &1))

      {results, failed} =
        matched
        |> Enum.group_by(fn {:match, %Shape{name: name, version: version}, _path, _reader} ->
          {name, version}
        end)
        |> Enum.map(&profile_shape(&1, fuzzy, ctx))
        |> Enum.unzip()

      {:ok,
       %Folders{
         results: results |> Enum.reject(&is_nil/1) |> Map.new(),
         skipped:
           Enum.map(unmatched, fn {:skip, path, reason} -> {path, reason} end) ++
             Enum.concat(failed)
       }}
    end
  end

  defp columns(shapes),
    do:
      Enum.reduce(shapes, %{}, fn %Shape{spec: spec}, acc ->
        Map.merge(acc, spec.header.columns)
      end)

  defp outcome({path, {:ok, %Classify.Result{verdict: :match, shape: shape, reader: reader}}}),
    do: {:match, shape, path, reader}

  defp outcome({path, {:ok, %Classify.Result{verdict: verdict}}}), do: {:skip, path, verdict}

  defp outcome({path, {:error, reason}}), do: {:skip, path, reason}

  defp shape_fuzzy(opts), do: opts |> Keyword.get(:fuzzy) |> shape_fuzzy(opts)

  defp shape_fuzzy(fuzzy, opts) when is_map(fuzzy), do: {fuzzy, Keyword.delete(opts, :fuzzy)}
  defp shape_fuzzy(_fuzzy, opts), do: {%{}, opts}

  defp validate_shape_fuzzy(fuzzy, shapes) do
    names = Enum.map(shapes, & &1.name)

    Enum.each(fuzzy, fn {name, threshold} ->
      validate_shape_name(name, names)
      Count.validate_fuzzy!(threshold)
    end)
  end

  defp validate_shape_name(name, names), do: known_shape(is_binary(name) and name in names, name)

  defp known_shape(true, _name), do: :ok

  defp known_shape(false, name) do
    raise ArgumentError, "fuzzy must name given shapes, got: #{inspect(name)}"
  end

  defp profile_shape(
         {{name, _version} = key, [{:match, shape, _path, _reader} | _] = matched},
         fuzzy,
         ctx
       ) do
    ctx = %{ctx | fuzzy: Map.get(fuzzy, name, ctx.fuzzy)}

    {counted, paths, failed} = Enum.reduce(matched, {{0, %{}}, [], []}, &count_file(&1, &2, ctx))

    {result(key, shape, Enum.reverse(paths), counted, ctx), Enum.reverse(failed)}
  end

  defp result(_key, _shape, [], _counted, _ctx), do: nil

  defp result(key, shape, paths, counted, ctx) do
    {rows, columns} = Count.finish(counted, :files, ctx)

    {key, %Result{shape: shape, files: paths, rows: rows, columns: columns}}
  end

  defp count_file({:match, shape, path, reader}, {counted, paths, failed}, %Ctx{} = ctx) do
    path
    |> read(shape, counted, reader, ctx)
    |> counted_file(path, {counted, paths, failed})
  end

  defp read(path, %Shape{spec: spec}, counted, {reader, reader_opts}, ctx),
    do: Reader.read(reader, path, reader_opts, &Count.add_file(counted, &1, path, spec, ctx))

  defp counted_file({:ok, counted}, path, {_counted, paths, failed}),
    do: {counted, [path | paths], failed}

  defp counted_file({:error, reason}, path, {counted, paths, failed}),
    do: {counted, paths, [{path, reason} | failed]}
end
