defmodule Refract.TestReaders.Txt do
  use Refract.Reader

  @impl Refract.Reader
  def open_options, do: Refract.CSV.open_options()

  @impl Refract.Reader
  def open(source, opts), do: Refract.CSV.open(source, opts)

  @impl Refract.Reader
  def extensions, do: ["txt"]
end

defmodule Refract.TestReaders.RefusesCsv do
  use Refract.Reader

  @impl Refract.Reader
  def open_options, do: []

  @impl Refract.Reader
  def open(_source, _opts), do: {:error, :refused}

  @impl Refract.Reader
  def extensions, do: ["csv"]
end

defmodule Refract.TestReaders.AlsoTxt do
  use Refract.Reader

  @impl Refract.Reader
  def open_options, do: []

  @impl Refract.Reader
  def open(_source, _opts), do: {:error, :refused}

  @impl Refract.Reader
  def extensions, do: ["txt"]
end

defmodule Refract.TestReaders.Crashing do
  use Refract.Reader

  @impl Refract.Reader
  def open_options, do: []

  @impl Refract.Reader
  def open(_source, _opts), do: raise("reader bug")

  @impl Refract.Reader
  def extensions, do: ["boom"]
end

defmodule Refract.TestReaders.Exiting do
  use Refract.Reader

  @impl Refract.Reader
  def open_options, do: []

  @impl Refract.Reader
  def open(_source, _opts), do: exit(:reader_down)

  @impl Refract.Reader
  def extensions, do: ["exit"]
end

defmodule Refract.TestReaders.Throwing do
  use Refract.Reader

  @impl Refract.Reader
  def open_options, do: []

  @impl Refract.Reader
  def open(_source, _opts), do: throw(:reader_bail)

  @impl Refract.Reader
  def extensions, do: ["throw"]
end

defmodule Refract.TestReaders.UpperCase do
  use Refract.Reader

  @impl Refract.Reader
  def open_options, do: []

  @impl Refract.Reader
  def open(_source, _opts), do: {:error, :refused}

  @impl Refract.Reader
  def extensions, do: ["TXT"]
end

defmodule Refract.TestReaders.Dotted do
  use Refract.Reader

  @impl Refract.Reader
  def open_options, do: []

  @impl Refract.Reader
  def open(_source, _opts), do: {:error, :refused}

  @impl Refract.Reader
  def extensions, do: [".txt"]
end

defmodule Refract.TestReaders.NoExtensions do
  use Refract.Reader

  @impl Refract.Reader
  def open_options, do: []

  @impl Refract.Reader
  def open(_source, _opts), do: {:error, :refused}
end

defmodule Refract.TestReaders.Memory do
  use Refract.Reader

  @enforce_keys [:lines]

  defstruct [:lines]

  @type t :: %__MODULE__{lines: [Refract.raw_row()]}

  @impl Refract.Reader
  def open_options, do: []

  @impl Refract.Reader
  def open(source, opts), do: opened(source, Keyword.validate!(opts, open_options()))

  @impl Refract.Reader
  def facts(%__MODULE__{lines: lines}, opts) do
    Keyword.validate!(opts, open_options())
    {:ok, %{lines: length(lines)}}
  end

  def facts(source, _opts), do: {:error, {:unsupported_source, source}}

  defp opened(%__MODULE__{lines: lines}, _opts), do: {:ok, lines}
  defp opened(source, _opts), do: {:error, {:unsupported_source, source}}

  @impl Refract.Reader
  def indexing, do: :records
end
