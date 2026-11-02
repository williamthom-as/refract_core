defmodule Refract.Validate.UniqueCostTest do
  use ExUnit.Case, async: false

  @moduletag timeout: 10_000

  alias Refract.CSV
  alias Refract.Shape
  alias Refract.Table
  alias Refract.Validate
  alias Refract.Validate.CrossRow
  alias Refract.Validate.Unique

  @traced [{CrossRow, :run, 3}, {Unique, :new, 2}]

  @source {:string, "account,qty\nA-1,1\nA-2,2\nA-1,3\n"}

  defp shape(columns) do
    Shape.new(
      name: "accounts",
      spec: Table.spec(header: [columns: %{"account" => ["account"], "qty" => ["qty"]}]),
      validation: [columns: columns]
    )
  end

  defp plain, do: shape(%{"account" => [:required], "qty" => [:integer]})

  defp unique, do: shape(%{"account" => [:required, :unique], "qty" => [:integer]})

  defp rows, do: [%{"account" => "A-1", "qty" => "1"}, %{"account" => "A-1", "qty" => "2"}]

  defp traced_calls(fun) do
    test_pid = self()
    tracer = spawn_link(fn -> collect([], test_pid) end)

    Enum.each(@traced, fn {module, _function, _arity} = mfa ->
      Code.ensure_loaded!(module)
      1 = :erlang.trace_pattern(mfa, true, [:local])
    end)

    :erlang.trace(self(), true, [:call, {:tracer, tracer}])

    fun.()

    :erlang.trace(self(), false, [:call])
    Enum.each(@traced, &:erlang.trace_pattern(&1, false, [:local]))

    send(tracer, :done)

    receive do
      {:calls, calls} -> calls
    end
  end

  defp collect(calls, test_pid) do
    receive do
      {:trace, _pid, :call, {module, function, args}} ->
        collect([{module, function, length(args)} | calls], test_pid)

      :done ->
        send(test_pid, {:calls, Enum.reverse(calls)})
    end
  end

  test "a shape without unique never builds a check or enters the cross row step" do
    assert traced_calls(fn -> rows() |> Validate.rows(plain()) |> Enum.to_list() end) == []
    assert traced_calls(fn -> CSV.validate(@source, plain()) end) == []
  end

  test "a shape with unique does, so the trace sees the calls" do
    assert {CrossRow, :run, 3} in traced_calls(fn ->
             rows() |> Validate.rows(unique()) |> Enum.to_list()
           end)

    assert {Unique, :new, 2} in traced_calls(fn -> CSV.validate(@source, unique()) end)
  end
end
