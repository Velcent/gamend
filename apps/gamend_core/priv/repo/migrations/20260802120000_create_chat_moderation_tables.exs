defmodule Gamend.Repo.Migrations.CreateChatModerationTables do
  @moduledoc """
  Chat moderation (see docs/specs/chat-moderation.md): an admin-managed word
  blocklist, a durable report queue, and scoped mutes.
  """
  use Ecto.Migration

  def up do
    create table(:chat_filter_words) do
      add :word, :string, null: false
      add :severity, :string, null: false, default: "block"
      add :match_mode, :string, null: false, default: "substring"
      # Provenance for bundled-list imports; matching itself is language-agnostic.
      add :lang, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:chat_filter_words, [:word])
    create index(:chat_filter_words, [:severity])
    # "Remove the German list" as a bulk action.
    create index(:chat_filter_words, [:lang])

    create table(:chat_reports) do
      # nil reporter means the word filter filed this report itself.
      add :reporter_id, references(:users, on_delete: :nilify_all)
      add :message_id, references(:chat_messages, on_delete: :nilify_all)
      add :reported_user_id, references(:users, on_delete: :delete_all), null: false
      # Chat content is capped at 4096 chars; :string would be varchar(255) on
      # Postgres. Denormalized so the queue survives message deletion.
      add :content_snapshot, :text
      add :reason, :string
      add :status, :string, null: false, default: "open"
      add :resolved_by, references(:users, on_delete: :nilify_all)
      add :resolution_note, :text
      add :resolved_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # The queue listing and the /admin counter read exactly this predicate.
    create index(:chat_reports, [:status],
             name: :chat_reports_open_index,
             where: "status = 'open'"
           )

    create index(:chat_reports, [:reported_user_id])
    create index(:chat_reports, [:reporter_id])
    create index(:chat_reports, [:inserted_at])

    # One report per player per message. Partial so the many system-filed
    # (reporter_id IS NULL) reports do not collide with each other.
    create unique_index(:chat_reports, [:reporter_id, :message_id],
             name: :chat_reports_reporter_message_index,
             where: "reporter_id IS NOT NULL AND message_id IS NOT NULL"
           )

    create table(:chat_mutes) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :scope, :string, null: false, default: "global"
      # Polymorphic (lobby/group/party), so it cannot be a references/2.
      add :scope_ref_id, :binary_id
      # nil means a permanent mute (mirrors ip_bans.expires_at).
      add :expires_at, :utc_datetime
      add :reason, :string
      add :muted_by, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:chat_mutes, [:user_id, :scope, :scope_ref_id],
             name: :chat_mutes_user_scope_ref_index
           )

    # NULL never equals NULL, so the composite index above does not constrain
    # global mutes. This one does.
    create unique_index(:chat_mutes, [:user_id, :scope],
             name: :chat_mutes_user_global_index,
             where: "scope_ref_id IS NULL"
           )

    # Expiry is filtered in the query, not in the index: a partial index on
    # `expires_at > now()` is not portable (SQLite has no now()).
    create index(:chat_mutes, [:user_id])
    create index(:chat_mutes, [:expires_at])
    create index(:chat_mutes, [:scope, :scope_ref_id])
  end

  def down do
    drop table(:chat_mutes)
    drop table(:chat_reports)
    drop table(:chat_filter_words)
  end
end
