defmodule Refract.Validate.CrossRow do
  @moduledoc false

  alias Refract.Validate.CrossRow.Ctx
  alias Refract.Validate.Unique

  @type check :: Unique.t()

  @spec run(Enumerable.t(), [check(), ...], boolean()) :: Enumerable.t()

  def run(rows, checks, values) do
    Stream.transform(rows, checks, fn row, checks ->
      checked_row(row, checks, values)
    end)
  end

  defp checked_row({row, line, issues}, checks, values) do
    ctx = %Ctx{
      line: line,
      failed: MapSet.new(issues, & &1.column),
      values: values
    }

    {checks, found} =
      Enum.map_reduce(checks, [], fn check, found ->
        {check_issues, check} = check_row(check, row, ctx)
        {check, found ++ check_issues}
      end)

    {[{row, issues ++ found}], checks}
  end

  defp check_row(%Unique{} = unique, row, ctx), do: Unique.check_row(unique, row, ctx)
end
