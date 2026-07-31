# `Gamend.Captcha`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/captcha.ex#L1)

Human verification for the unauthenticated browser forms, via
[Cloudflare Turnstile](https://developers.cloudflare.com/turnstile/).

Off by default. It guards the two paths that mail an address the submitter
chose — registration and the magic link — where the abuse is not "too many
requests from one IP" (the rate limiter in `GamendWeb.LiveHelpers`
already answers that) but a botnet spending our mail reputation an address
at a time. Password login is deliberately *not* guarded: a captcha on every
routine sign-in is friction for returning players, and the credentials are
their own proof.

The game SDKs never see this. Registration is browser-only (there is no
`POST /api/v1/register`), and device login is untouched, so turning it on
cannot break a shipped Godot or JS client.

## Setup

Create a widget at <https://dash.cloudflare.com/?to=/:account/turnstile> —
it is free with no request cap and no card — then set:

    GAMEND_CAPTCHA_ENABLED=true
    GAMEND_CAPTCHA_SITE_KEY=0x4AAA...
    GAMEND_CAPTCHA_SECRET_KEY=0x4AAA...

Dev and test need none of that: with the keys unset we fall back to
Cloudflare's published dummy pair, which passes on any host including
localhost. That keeps the widget on the page in development, so a form that
only breaks once a captcha is in front of it breaks on the developer's
machine rather than in production. To exercise the failure path, set
`GAMEND_CAPTCHA_SECRET_KEY` to the always-fails dummy,
`2x0000000000000000000000000000000AA`.

# `error`

```elixir
@type error() :: :missing | :invalid | :unavailable
```

Why a token was rejected. `:missing` never reached Cloudflare.

# `enabled?`

```elixir
@spec enabled?() :: boolean()
```

Whether the register and magic-link forms require a captcha.

# `script_origin`

```elixir
@spec script_origin() :: String.t()
```

The host the widget script is served from, for the browser CSP.

# `site_key`

```elixir
@spec site_key() :: String.t()
```

The sitekey to render, falling back to the always-passes dummy.

# `verify`

```elixir
@spec verify(term(), String.t() | nil) :: :ok | {:error, error()}
```

Verifies a widget token with Cloudflare.

Returns `:ok` when the token is good, `{:error, reason}` otherwise. When
the captcha is disabled this is `:ok` without a network call, so callers can
gate unconditionally rather than branching on `enabled?/0` themselves.

`remote_ip` is passed through to Cloudflare when known; `"unknown"` (what
`GamendWeb.LiveHelpers.client_ip/1` returns without peer data) is
omitted rather than sent as a literal.

A token is single-use and expires after five minutes, so a rejected
submission needs a fresh one — the caller resets the widget.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
