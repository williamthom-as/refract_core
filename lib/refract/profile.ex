defmodule Refract.Profile do
  @moduledoc """
  finds values in a column that look like spellings of one value, and the lines they are on.
  reads only, fixes nothing.

  - every shape column found in the file; `except:` leaves columns out; `columns: :all` also
    profiles header cells the shape does not name, under their header text
  - a cluster groups values equal after case, spacing, punctuation and accents; different digits
    never group
  - lines are file lines; `max_lines:` per variant, `max_distinct:` per column
  - every value is listed, spelt one way or many; `singles: :drop` keeps only the ones spelt more than one way
  - `folder/3` profiles every file a shape matched as one, lines by file; a result per shape name
    and version, unmatched or unreadable files listed in `skipped`
  - `rows/1` + `header/0` flatten a result to rows for any writer

      {:ok, result} = Refract.CSV.profile("ledger.csv", MyApp.Shapes.Ledger, except: ["notes"])
      Refract.Profile.lines(lines, ledger)
      {:ok, %Refract.Profile.Folders{results: results, skipped: skipped}} = Refract.Profile.folder("inbox/", [ledger])
      Refract.CSV.write(Refract.Profile.rows(result), "report.csv", header: Refract.Profile.header())
  """

  alias Refract.Profile.Count
  alias Refract.Profile.Folder
  alias Refract.Profile.Folders
  alias Refract.Profile.Report
  alias Refract.Profile.Result
  alias Refract.Shape
  alias Refract.Table.Locate

  @spec lines(Enumerable.t(), Shape.t() | module(), [Count.opt()]) ::
          {:ok, Result.t()} | {:error, {:header_not_found, Locate.header_miss()}}

  def lines(raw, shape, opts \\ []), do: Count.run(raw, shape, opts)

  @spec folder(Path.t(), [Shape.t() | module()], [Folder.opt()]) ::
          {:ok, Folders.t()} | {:error, term()}

  def folder(dir, shapes, opts \\ []), do: Folder.run(dir, shapes, opts)

  @spec rows(Result.t() | Folders.t()) :: [%{String.t() => term()}]

  def rows(result), do: Report.rows(result)

  @spec header() :: [String.t()]

  def header, do: Report.header()
end
