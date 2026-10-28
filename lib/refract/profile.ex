defmodule Refract.Profile do
  @moduledoc """
  finds values in a column that look like spellings of one value, and the lines they are on.
  reads only, fixes nothing.

  - every shape column found in the file; `except:` leaves columns out
  - a cluster groups values equal after case, spacing, punctuation and accents; different digits
    never group
  - lines are file lines; `max_lines:` per variant, `max_distinct:` per column

      {:ok, result} = Refract.CSV.profile("ledger.csv", MyApp.Shapes.Ledger, except: ["notes"])
      Refract.Profile.lines(lines, ledger)
  """

  alias Refract.Profile.Count
  alias Refract.Profile.Result
  alias Refract.Shape
  alias Refract.Table.Locate

  @spec lines(Enumerable.t(), Shape.t() | module(), [Count.opt()]) ::
          {:ok, Result.t()} | {:error, {:header_not_found, Locate.header_miss()}}

  def lines(raw, shape, opts \\ []), do: Count.run(raw, shape, opts)
end
