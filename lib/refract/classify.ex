defmodule Refract.Classify do
  @moduledoc """
  says which shape a file is. if none, why. reads only the first `within:` lines.

  - every shape is a candidate, ranked, with its header and row reports
  - verdict `:match`, `:ambiguous` (within `margin:`) or `:unknown` (closest shape + reason)
  - score is header share times row pass rate; under `min_score:` is `:rows_failed`
  - row cells are left out of reports unless `values: true`

      {:ok, result} = Refract.CSV.classify("bill.csv", [MyApp.Shapes.Bill, invoice])
      Refract.Classify.lines(lines, [invoice])
  """

  alias Refract.Classify.Folder
  alias Refract.Classify.Mapping
  alias Refract.Classify.Result
  alias Refract.Classify.Score
  alias Refract.Classify.Suggest
  alias Refract.Shape

  @spec lines(Enumerable.t(), [Shape.t() | module()], [Score.opt()]) :: Result.t()

  def lines(raw, shapes, opts \\ []), do: Score.run(raw, shapes, opts)

  @spec folder(Path.t(), [Shape.t() | module()], [Folder.opt()]) ::
          {:ok, Enumerable.t(Folder.item())} | {:error, term()}

  def folder(dir, shapes, opts \\ []), do: Folder.run(dir, shapes, opts)

  @spec suggest(Enumerable.t(), Shape.t() | module(), [Suggest.opt()]) :: Mapping.t()
end
