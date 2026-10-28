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
    {profile_opts, folder_opts} = Keyword.split(opts, [:except, :max_distinct, :max_lines])
    resolved_shapes = Shape.resolve_all(shapes)
    readers = Keyword.get(folder_opts, :readers, [])

    ctx =
      Count.ctx!(profile_opts ++ Keyword.take(folder_opts, [:within]), columns(resolved_shapes))

    with {:ok, classified} <- Classify.folder(dir, resolved_shapes, folder_opts) do
      {matched, unmatched} =
        classified
        |> Enum.map(&outcome/1)
        |> Enum.split_with(&match?({:match, _shape, _path}, &1))

      {results, failed} =
        matched
        |> Enum.group_by(fn {:match, %Shape{name: name, version: version}, _path} ->
          {name, version}
        end)
        |> Enum.map(&profile_shape(&1, readers, ctx))
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

  defp outcome({path, {:ok, %Classify.Result{verdict: :match, shape: shape}}}),
    do: {:match, shape, path}

  defp outcome({path, {:ok, %Classify.Result{verdict: verdict}}}), do: {:skip, path, verdict}
  defp outcome({path, {:error, reason}}), do: {:skip, path, reason}

  defp profile_shape({key, [{:match, shape, _path} | _] = matched}, readers, ctx) do
    {counted, paths, failed} =
      Enum.reduce(matched, {{0, %{}}, [], []}, &count_file(&1, &2, readers, ctx))

    {result(key, shape, Enum.reverse(paths), counted), Enum.reverse(failed)}
  end

  defp result(_key, _shape, [], _counted), do: nil

  defp result(key, shape, paths, counted) do
    {rows, columns} = Count.finish(counted, :files)

    {key, %Result{shape: shape, files: paths, rows: rows, columns: columns}}
  end

  defp count_file({:match, shape, path}, {counted, paths, failed}, readers, %Ctx{} = ctx) do
    path
    |> read(shape, counted, readers, ctx)
    |> counted_file(path, {counted, paths, failed})
  end

  defp read(path, %Shape{spec: spec}, counted, readers, ctx) do
    with {:ok, {reader, reader_opts}} <- Reader.for_path(path, readers),
         do: Reader.read(reader, path, reader_opts, &Count.add_file(counted, &1, path, spec, ctx))
  end

  defp counted_file({:ok, counted}, path, {_counted, paths, failed}),
    do: {counted, [path | paths], failed}

  defp counted_file({:error, reason}, path, {counted, paths, failed}),
    do: {counted, paths, [{path, reason} | failed]}
end
