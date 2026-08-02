defmodule Gamend.Chat.Report do
  @moduledoc """
  Chat report struct from Gamend.

  This is a stub module for SDK type definitions. The actual struct
  is provided by Gamend at runtime.

  ## Fields

  - `id` - Report ID (string, UUID)
  - `reporter_id` - Player who filed it, or `nil` when the word filter did (string)
  - `message_id` - Reported message, `nil` once that message is deleted (string)
  - `reported_user_id` - Author of the reported message (string)
  - `content_snapshot` - The message text as it was when reported (string)
  - `reason` - Why it was reported (string)
  - `status` - `"open"`, `"reviewing"`, `"actioned"` or `"dismissed"` (string)
  - `resolved_by` - Moderator who resolved it (string)
  - `resolution_note` - Note left by the moderator (string)
  - `resolved_at` - When it was resolved
  - `inserted_at` - Creation timestamp
  - `updated_at` - Last update timestamp
  """

  @type t :: %__MODULE__{
          id: String.t(),
          reporter_id: String.t() | nil,
          message_id: String.t() | nil,
          reported_user_id: String.t(),
          content_snapshot: String.t() | nil,
          reason: String.t() | nil,
          status: String.t(),
          resolved_by: String.t() | nil,
          resolution_note: String.t() | nil,
          resolved_at: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :reporter_id,
    :message_id,
    :reported_user_id,
    :content_snapshot,
    :reason,
    :status,
    :resolved_by,
    :resolution_note,
    :resolved_at,
    :inserted_at,
    :updated_at
  ]
end
