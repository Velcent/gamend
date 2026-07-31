# `Gamend.Storage.Local`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/storage/local.ex#L1)

Disk-backed storage — the default backend.

Files live under `STORAGE_LOCAL_DIR` (default `priv/storage`). Readable URLs
and upload tickets point at the app itself. The upload endpoint is protected
by the caller's own auth plus a namespace check (a client may only write keys
under its own id), so the client flow matches S3 without a separate signed
token — an S3 presigned `PUT` simply ignores the extra auth header.

# `root_dir`

```elixir
@spec root_dir() :: String.t()
```

Directory objects are written to.

Reads the declared `:dir` setting, so `GAMEND_STORAGE_DIR` and the documented
default are the single source of truth. The previous fallback here pointed at
the *application's* priv directory, which is a different path from the
declared `priv/storage` default — and inside a release it is a versioned
directory that a deploy replaces, silently taking every stored object with it.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
