defmodule Gamend.Chat.Mute do
  @moduledoc """
  Chat mute struct from Gamend.

  This is a stub module for SDK type definitions. The actual struct
  is provided by Gamend at runtime.

  ## Fields

  - `id` - Mute ID (string, UUID)
  - `user_id` - The muted player (string)
  - `scope` - `"global"`, `"lobby"`, `"group"` or `"party"` (string)
  - `scope_ref_id` - The room id, `nil` for a global mute (string)
  - `expires_at` - When it lifts, `nil` for a permanent mute
  - `reason` - Why the player was muted (string)
  - `muted_by` - Who applied it, `nil` when a plugin did (string)
  - `inserted_at` - Creation timestamp
  - `updated_at` - Last update timestamp
  """

  @type t :: %__MODULE__{
          id: String.t(),
          user_id: String.t(),
          scope: String.t(),
          scope_ref_id: String.t() | nil,
          expires_at: DateTime.t() | nil,
          reason: String.t() | nil,
          muted_by: String.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :user_id,
    :scope,
    :scope_ref_id,
    :expires_at,
    :reason,
    :muted_by,
    :inserted_at,
    :updated_at
  ]
end
