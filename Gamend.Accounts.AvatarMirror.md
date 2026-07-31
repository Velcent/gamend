# `Gamend.Accounts.AvatarMirror`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/avatar_mirror.ex#L1)

Oban worker that mirrors a user's external (OAuth provider) avatar into our
own object storage, so avatars render from our storage/CDN instead of
hotlinking the provider.

Enqueued on sign-in whenever a user's avatar is still an external URL (see
`Gamend.Accounts.maybe_mirror_avatar/1`). Once mirrored the stored URL
lives under our own `avatars/<user_id>/` prefix, so the check short-circuits
and we never re-fetch an avatar we already host.

A *failed* mirror is a different matter from a finished one. Provider CDNs
rate-limit (Google answers 429 readily), so the download is retried with
backoff, and a run that exhausts its attempts does not poison the user
forever — the next sign-in enqueues a fresh job. Until one succeeds the
provider URL stays as the fallback, which is why an un-mirrored avatar can
still 429 in the browser.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
