defmodule Refract.Profile do
  @moduledoc """
  finds values in a column that look like spellings of one value, and the lines they are on.
  reads only, fixes nothing.

  - every shape column found in the file; `except:` leaves columns out; `columns: :all` also
    profiles header cells the shape does not name, under the names `stream` gives them (`except:`
    then names header text and is not checked against the shape; `ignore:` cells stay out)
  - a cluster groups values equal after case, spacing, punctuation and accents; different digits
    never group
  - lines are file lines; `max_lines:` per variant, `max_distinct:` per column
  - `values: true` lists every distinct value with its count and lines, an inventory of the column;
    `rows(result, :values)` + `header(:values)` write it
  - `fuzzy: 0.9` looser, `fuzzy: false` off (`Column.fuzzy` says `:done`, `:skipped` or `:off`); a
    folder takes `%{"shape name" => 0.9 | false}`
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

  @spec rows(Result.t() | Folders.t(), :values) :: [%{String.t() => term()}]

  def rows(result, :values), do: Report.rows(result, :values)

  @spec header(:values) :: [String.t()]

  def header(:values), do: Report.header(:values)
end
