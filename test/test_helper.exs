exclude =
  for {tag, module} <- [duckdb: Duckdbex, yaml: YamlElixir] do
    if Code.ensure_loaded?(module), do: :"without_#{tag}", else: tag
  end

ExUnit.start(exclude: exclude)
