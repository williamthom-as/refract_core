defmodule Refract.CSV.ContractTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 5_000

  defp csv_module?(module) do
    name = Atom.to_string(module)

    name == "Elixir.Refract.CSV" or String.starts_with?(name, "Elixir.Refract.CSV.")
  end

  defp core_module?(module),
    do: String.starts_with?(Atom.to_string(module), "Elixir.Refract.") and not csv_module?(module)

  defp core_calls(module) do
    {:ok, {^module, [imports: imports]}} = :beam_lib.chunks(:code.which(module), [:imports])

    for {called, _fun, _arity} = call <- imports, core_module?(called), do: call
  end

  defp internal?({module, fun, arity}) do
    {:docs_v1, _anno, _language, _format, module_doc, _meta, docs} = Code.fetch_docs(module)

    module_doc == :hidden or
      Enum.any?(docs, &match?({{_kind, ^fun, ^arity}, _anno, _signature, :hidden, _meta}, &1))
  end

  describe "contract" do
    test "csv calls only public core functions" do
      {:ok, modules} = :application.get_key(:refract, :modules)

      internal =
        for module <- modules,
            csv_module?(module),
            call <- core_calls(module),
            internal?(call),
            uniq: true,
            do: call

      assert internal == []
    end
  end
end
