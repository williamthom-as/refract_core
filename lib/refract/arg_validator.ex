defmodule Refract.ArgValidator do
  @moduledoc false

  @spec validate_positive_integer!(term(), atom()) :: :ok

  def validate_positive_integer!(value, _name) when is_integer(value) and value > 0, do: :ok

  def validate_positive_integer!(value, name) do
    raise ArgumentError, "#{name} must be a positive integer, got: #{inspect(value)}"
  end

  @spec validate_non_negative_integer!(term(), atom()) :: :ok

  def validate_non_negative_integer!(value, _name) when is_integer(value) and value >= 0, do: :ok

  def validate_non_negative_integer!(value, name) do
    raise ArgumentError, "#{name} must be a non negative integer, got: #{inspect(value)}"
  end

  @spec validate_boolean!(term(), atom()) :: :ok

  def validate_boolean!(value, _name) when is_boolean(value), do: :ok

  def validate_boolean!(value, name) do
    raise ArgumentError, "#{name} must be true or false, got: #{inspect(value)}"
  end

  @spec validate_fraction!(term(), atom()) :: :ok

  def validate_fraction!(value, _name) when is_number(value) and value >= 0 and value <= 1,
    do: :ok

  def validate_fraction!(value, name) do
    raise ArgumentError, "#{name} must be a number from 0 to 1, got: #{inspect(value)}"
  end
end
