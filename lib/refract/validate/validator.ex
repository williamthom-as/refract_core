defmodule Refract.Validate.Validator do
  @moduledoc """
  behaviour for a custom validation rule. implement `valid?/2` then use the module where a
  column or field rule goes, as `{MyValidator, opts}` or the bare optless `MyValidator`.

  a blank cell skips it (list `:required` too to catch blanks), a raise fails the rule.

      defmodule MyApp.Validators.PostCode do
        @behaviour Refract.Validate.Validator

        @impl true
        def valid?(cell, _opts), do: Regex.match?(~r/^\\d{4}$/, cell)
      end

      validation: [columns: %{"post_code" => [:required, MyApp.Validators.PostCode]}]
  """

  import Refract.Utils, only: [exports?: 3]

  @callback valid?(cell :: Refract.cell(), opts :: keyword()) :: boolean()

  @spec validator?(term()) :: boolean()

  def validator?(module), do: exports?(module, :valid?, 2)
end
