# `mix gamend.content.migrate_metadata`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/mix/tasks/gamend.content.migrate_metadata.ex#L1)

One-shot migration for instances that stored translations in the database.

    mix gamend.content.migrate_metadata            # write them into the PO files
    mix gamend.content.migrate_metadata --dry-run  # report only
    mix gamend.content.migrate_metadata --prune    # also clear the metadata keys

Quests and leaderboards used to carry a second, per-locale copy of their text
in `metadata["titles"][locale]` and `metadata["descriptions"][locale]`, edited
through the admin. That is the same duplicate-store problem the theme had: a
title edited in the admin left 29 stale copies behind it, and nothing could
tell you which were stale.

Translations now live in the `content` gettext domain, keyed by the source
string. This lifts whatever is in the database into
`priv/gettext/<locale>/LC_MESSAGES/content.po` so that curated work is not
lost, **merging** rather than overwriting: an existing translation is never
replaced, and a msgid that is not in the PO yet is appended.

Run it once, check the diff, then re-run with `--prune` to clear the now-dead
metadata keys. Without `--prune` the keys stay behind, inert - nothing reads
them any more.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
