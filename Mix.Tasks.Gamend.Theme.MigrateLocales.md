# `mix gamend.theme.migrate_locales`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/mix/tasks/gamend.theme.migrate_locales.ex#L1)

One-shot migration off one-JSON-file-per-locale.

    mix gamend.theme.migrate_locales theme/config.json
    mix gamend.theme.migrate_locales theme/config.json --dry-run

For each `<base>.<locale>.json` sitting next to the base config, pairs every
translatable leaf with the same leaf in the base by **path**, and writes
`msgid <base text> / msgstr <localised text>` into that locale's `theme.po`.

Path-pairing is safe here and only here: the locale files were copies of the
base, so identical paths held corresponding text. Ongoing translation keys on
the source string instead, which is what survives a section being reordered.

Reports anything it could not pair rather than guessing — a path present in a
locale but not the base means the two drifted, and a human should look.

Delete the locale files once this has run; nothing reads them any more.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
