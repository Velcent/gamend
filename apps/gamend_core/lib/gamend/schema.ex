defmodule Gamend.Schema do
  @moduledoc """
  Shared schema base: `use Gamend.Schema` instead of `use Ecto.Schema`.

  Sets UUIDv7 primary and foreign keys (see `Gamend.UUIDv7`) so ids are
  time-ordered but not enumerable.
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @primary_key {:id, Gamend.UUIDv7, autogenerate: true}
      @foreign_key_type Gamend.UUIDv7
    end
  end
end
