defmodule Refract.Classify do
  @moduledoc """
  says which shape a file is. if none, why. reads only the first `within:` lines.

  - every shape is a candidate, ranked, with its header and row reports
  - verdict `:match`, `:ambiguous` (within `margin:`) or `:unknown` (closest shape + reason)
  - score is header share (columns found over columns needed, at most 1) times row pass rate;
    under `min_score:` is `:rows_failed`
  - `:unknown` names the closest shape when its header was found or it scores `min_score:`
  - row cells are left out of reports unless `values: true`

      {:ok, result} = Refract.CSV.classify("bill.csv", [MyApp.Shapes.Bill, invoice])
      Refract.Classify.lines(lines, [invoice])
  """

  alias Refract.Classify.Folder
  alias Refract.Classify.Result
  alias Refract.Classify.Score
  alias Refract.Classify.Suggest
  alias Refract.Shape
  alias Refract.Table.Report.Line

  @spec lines(Enumerable.t(), [Shape.t() | module()], [Score.opt()]) :: Result.t()

  def lines(raw, shapes, opts \\ []), do: Score.run(raw, shapes, opts)

  @spec folder(Path.t(), [Shape.t() | module()], [Folder.opt()]) ::
          {:ok, Enumerable.t(Folder.item())} | {:error, term()}

  def folder(dir, shapes, opts \\ []), do: Folder.run(dir, shapes, opts)

  @spec suggest(Enumerable.t(), Shape.t() | module(), [Suggest.opt()]) :: Line.t()

  def suggest(raw, shape, opts \\ []), do: Suggest.run(raw, shape, opts)
end
