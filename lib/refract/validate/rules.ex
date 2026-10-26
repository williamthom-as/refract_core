defmodule Refract.Validate.Rules do
  @moduledoc false

  alias Refract.Parse.Date, as: DateParser
  alias Refract.Table.Spec.Row
  alias Refract.Validate.Validator

  import Refract.Table.Spec.Row, only: [is_type_rule: 1]

  @type rule ::
          :required
          | :integer
          | :number
          | :date
          | :datetime
          | Regex.t()
          | {:min | :max, number() | Decimal.t() | Date.t()}
          | {:in, [term()]}
          | {:date | :datetime, [DateParser.format()]}
          | {atom(), (Refract.cell() -> as_boolean(term()))}
          | module()
          | {module(), keyword()}

  @type row_rule :: {atom(), (Refract.row() -> as_boolean(term()))}

  @type document :: %{fields: %{String.t() => Refract.cell()}, rows: [Refract.row()]}

  @type document_rule :: {atom(), (document() -> as_boolean(term()))}

  @type t :: %__MODULE__{
          columns: %{String.t() => [rule()]},
          rows: [row_rule()],
          document: [document_rule()]
        }

  defstruct columns: %{}, rows: [], document: []

  @spec new!(keyword(), %{String.t() => term()}) :: t()

  def new!(opts, column_names) do
    opts = Keyword.validate!(opts, columns: %{}, rows: [], document: [])

    columns = Keyword.fetch!(opts, :columns)
    rows = Keyword.fetch!(opts, :rows)
    document = Keyword.fetch!(opts, :document)

    validate_columns(columns, column_names)

    Enum.each(rows, &validate_row_rule/1)
    Enum.each(document, &validate_document_rule/1)

    %__MODULE__{columns: columns, rows: rows, document: document}
  end

  @spec validate_rules!([rule()]) :: :ok

  def validate_rules!(rules) when is_list(rules), do: Enum.each(rules, &validate_rule/1)

  def validate_rules!(rules) do
    raise ArgumentError, "rules must be a list, got: #{inspect(rules)}"
  end

  defp validate_columns(columns, column_names) do
    Enum.each(columns, fn {column, rules} ->
      validate_column(column, column_names)
      validate_rules!(rules)
    end)
  end

  defp validate_column(column, column_names) when is_map_key(column_names, column), do: :ok

  defp validate_column(column, _column_names) do
    raise ArgumentError, "validation rule for unknown column #{column}"
  end

  defp validate_rule(:required), do: :ok
  defp validate_rule(rule) when is_type_rule(rule), do: Row.validate_type_rule!(rule)
  defp validate_rule(%Regex{}), do: :ok
  defp validate_rule({bound, n}) when bound in [:min, :max] and is_number(n), do: :ok
  defp validate_rule({bound, %Decimal{}}) when bound in [:min, :max], do: :ok
  defp validate_rule({bound, %Date{}}) when bound in [:min, :max], do: :ok
  defp validate_rule({:in, values}) when is_list(values), do: :ok
  defp validate_rule({name, fun}) when is_atom(name) and is_function(fun, 1), do: :ok

  defp validate_rule(fun) when is_function(fun) do
    raise ArgumentError,
          "a function rule must be named, {name, fn cell -> boolean end}, got: #{inspect(fun)}"
  end

  defp validate_rule({module, opts} = rule) when is_atom(module) and is_list(opts),
    do: validate_validator(Validator.validator?(module), Keyword.keyword?(opts), rule)

  defp validate_rule(module) when is_atom(module),
    do: validate_validator(Validator.validator?(module), true, module)

  defp validate_rule(rule) do
    raise ArgumentError, "unknown validation rule #{inspect(rule)}"
  end

  defp validate_validator(true, true, _rule), do: :ok

  defp validate_validator(_validator, _keyword, rule) do
    raise ArgumentError,
          "unknown validation rule #{inspect(rule)}, a module rule must implement " <>
            "Refract.Validate.Validator and take a keyword list of options"
  end

  defp validate_row_rule({name, fun}) when is_atom(name) and is_function(fun, 1), do: :ok

  defp validate_row_rule(rule) do
    raise ArgumentError, "a row rule must be {name, fn row -> boolean end}, got: #{inspect(rule)}"
  end

  defp validate_document_rule({name, fun}) when is_atom(name) and is_function(fun, 1), do: :ok

  defp validate_document_rule(rule) do
    raise ArgumentError,
          "a document rule must be {name, fn document -> boolean end}, got: #{inspect(rule)}"
  end
end
