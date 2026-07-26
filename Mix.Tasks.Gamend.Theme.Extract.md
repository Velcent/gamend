# `mix gamend.theme.extract`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/mix/tasks/gamend.theme.extract.ex#L1)

Writes `theme.pot` from the strings in the theme config.

    mix gamend.theme.extract          # write the template
    mix gamend.theme.extract --check  # fail if it is out of date
    mix gamend.theme.extract -o PATH  # write somewhere else

`mix gettext.extract` cannot find these: it scans source for `gettext(...)`
calls, and theme text lives in data. This walks the config instead, using the
same `GameServer.Theme.Translatable` list the renderer uses, so the strings a
translator is offered are exactly the strings the server will translate.

Merge into the per-locale PO files afterwards the usual way:

    mix gettext.merge priv/gettext

---

*Consult [api-reference.md](api-reference.md) for complete listing*
