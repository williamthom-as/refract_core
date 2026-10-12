defmodule Refract.TestReaders.Txt do
  use Refract.Reader

  @impl Refract.Reader
  def open(source, opts), do: Refract.CSV.open(source, opts)

  @impl Refract.Reader
  def extensions, do: ["txt"]
end

defmodule Refract.TestReaders.RefusesCsv do
  use Refract.Reader

  @impl Refract.Reader
  def open(_source, _opts), do: {:error, :refused}

  @impl Refract.Reader
  def extensions, do: ["csv"]
end

defmodule Refract.TestReaders.AlsoTxt do
  use Refract.Reader

  @impl Refract.Reader
  def open(_source, _opts), do: {:error, :refused}

  @impl Refract.Reader
  def extensions, do: ["txt"]
end

defmodule Refract.TestReaders.Crashing do
  use Refract.Reader

  @impl Refract.Reader
  def open(_source, _opts), do: raise("reader bug")

  @impl Refract.Reader
  def extensions, do: ["boom"]
end

defmodule Refract.TestReaders.Exiting do
  use Refract.Reader

  @impl Refract.Reader
  def open(_source, _opts), do: exit(:reader_down)

  @impl Refract.Reader
  def extensions, do: ["exit"]
end

defmodule Refract.TestReaders.Throwing do
  use Refract.Reader

  @impl Refract.Reader
  def open(_source, _opts), do: throw(:reader_bail)

  @impl Refract.Reader
  def extensions, do: ["throw"]
end

defmodule Refract.TestReaders.UpperCase do
  use Refract.Reader

  @impl Refract.Reader
  def open(_source, _opts), do: {:error, :refused}

  @impl Refract.Reader
  def extensions, do: ["TXT"]
end

defmodule Refract.TestReaders.Dotted do
  use Refract.Reader

  @impl Refract.Reader
  def open(_source, _opts), do: {:error, :refused}

  @impl Refract.Reader
  def extensions, do: [".txt"]
end

defmodule Refract.TestReaders.NoExtensions do
  use Refract.Reader

  @impl Refract.Reader
  def open(_source, _opts), do: {:error, :refused}
end
