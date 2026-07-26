# `mix gamend.settings.guide`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/mix/tasks/gamend.settings.guide.ex#L1)

Writes the public Settings guide from `GameServer.Settings.all/0`.

    mix gamend.settings.guide          # write the guide
    mix gamend.settings.guide --check  # fail if it is out of date
    mix gamend.settings.guide -o PATH  # write somewhere else

Sibling of `mix gamend.settings.env_example`, for the same reason: the
guides used to hand-list environment variables, and every rename left them
describing variables the server no longer read. A declared setting is now
documented for readers of the docs site the moment it exists.

**Only for hosts that have a docs site.** When `priv/docs/60-operations`
does not exist the task says so and does nothing, including under `--check`
— a game built on this server has its own docs, or none, and should not have
a `priv/docs` tree conjured for it. Pass `-o PATH` to write somewhere else
deliberately; an explicit path is always honoured.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
