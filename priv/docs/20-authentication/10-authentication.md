---
icon: hero-finger-print
---

# Authentication

The platform supports multiple authentication methods. All API authentication uses JWT tokens (access + refresh). Browser sessions use cookie-based session tokens.

## Supported methods

- **Email / Password** — registration in the browser with a confirmation email,
  or from a game client with `POST /api/v1/register`
- **Magic link** — passwordless login via email link
- **Device token** — anonymous / guest authentication via unique device IDs
- **OAuth** — Discord, Google, Apple, Facebook, Steam

A provider goes live once its credentials are set (see its setup page in this
section); its sign-in buttons, `/auth/<provider>` routes, and the
`GET /api/v1/auth/providers` listing follow automatically. Set
`GAMEND_OAUTH_<PROVIDER>_ENABLED=false` to switch one off while keeping its
credentials.

An optional **captcha** (see below) protects the browser registration and
magic-link forms; it does not apply to any of the game-client flows.

## JWT token flow (Email / Password / Device)

A game client signs a player up with `POST /api/v1/register` (`email`,
`password`, optional `username`). It sends the confirmation email as the
browser form does and answers `201` with the same tokens as login; a taken
email or username is `409`, and an email that cannot be sent is `503` with no
account kept.
Deleting an account (`DELETE /api/v1/me`) sends `current_password` when the
account has one.

```text
  1. LOGIN
     Client ──► POST /api/v1/login         ──►   Verify credentials
                (email + password)                 │
                                                   ▼
            ◄── { access_token, refresh_token } ◄─ Guardian signs JWT

  2. AUTHENTICATED REQUEST
     Client ──► GET /api/v1/me              ──► Guardian verifies token
                Authorization: Bearer {token}      │
                                                   ▼
            ◄── { user data }                 ◄── Load user from claims

  3. TOKEN REFRESH
     Client ──► POST /api/v1/refresh         ──► Guardian exchanges token
                { refresh_token }                  │
                                                   ▼
            ◄── { access_token, refresh_token } ◄─ New access token
```

Access tokens are short-lived (15 min). Refresh tokens last 30 days. Both are signed JWTs, but each authenticated request still loads the user from the database. So a token stops working once the account is deactivated or its tokens are revoked (logout, password or email change).

Refresh returns a new access token and sends back the same refresh token; it does not issue a new one. Log in again before the refresh token's 30 days run out.

Token responses wrap their fields in a `data` object (`{"data": {"access_token": "..."}}`); the diagrams leave that wrapper out.

## OAuth: browser redirect (polling)

For game clients that can't handle OAuth natively. The client opens a browser, then polls for the result.

```text
  Client ──► GET /api/v1/auth/{provider}
         ◄── { session_id, authorization_url }

  Client ──► Opens authorization_url in browser
             Browser ──► OAuth Provider ──► User authenticates
             Provider ──► Callback to server
             Server stores result in DB

  Client ──► GET /api/v1/auth/session/{session_id}   (poll)
         ◄── { status: "pending", session: null }    (repeat)
         ◄── { status: "completed", session: { access_token, refresh_token, ... } }
```

`session` is the same `Session` email login answers, served once: later polls
say `completed` with `session: null`. A sign-in the server refuses ends as
`status: "error"` with a code in `error` (`account_not_activated`,
`sign_in_failed`, `authentication_failed`) and prose in `message`.

## OAuth: direct code exchange

For clients that handle OAuth natively (mobile SDKs, Steam auth tickets). No browser or polling needed.

```text
  Client ──► Initiates OAuth via native SDK
  Provider ──► Returns authorization code to client

  Client ──► POST /api/v1/auth/{provider}/callback  { code: "..." }
         ◄── { access_token, refresh_token, user_id, username, display_name }
```

Native Google (`POST /api/v1/auth/google/id_token`, `{id_token}`) and native
Apple (`POST /api/v1/auth/apple/ios/callback`, `{code}`) answer the same. For
Steam, `code` is the hex ticket from `ISteamUser::GetAuthTicketForWebApi`.

Every one of these signs in, finding or creating the account. A bearer token
on the request changes nothing; linking is its own endpoint.

## Provider linking

A signed-in player can add providers to their account, and unlink them later.
The user table stores provider IDs as nullable fields (discord_id, google_id,
apple_id, facebook_id, steam_id, device_id). Linking mirrors signing in, under
`/api/v1/me` and with the player's bearer token:

| Sign in (`/api/v1/auth`) | Link (`/api/v1/me/providers`) |
| --- | --- |
| `POST /{provider}/callback` `{code}` | `POST /{provider}` `{code}` |
| `POST /google/id_token` `{id_token}` | `POST /google/id_token` `{id_token}` |
| `POST /apple/ios/callback` `{code}` | `POST /apple/ios` `{code}` |
| `GET /{provider}`, then poll `GET /session/{id}` | `POST /{provider}/authorize`, then poll `GET /sessions/{id}` |

A link answers the whole current user, whose `linked_providers` shows the new
one, and pushes `user_updated` on the user channel. A provider account that
already belongs to another player is `409 provider_already_linked`; a polled
link ends with that code in `error`. `DELETE /api/v1/me/providers/{provider}`
unlinks, refusing the last provider (`last_auth_method`); `POST` and
`DELETE /api/v1/me/device` do the same for the device id.

## Captcha

Optional human verification on the browser sign-up forms, using
[Cloudflare Turnstile](https://developers.cloudflare.com/turnstile/). Off by
default.

It guards the two paths that send an email to an address the submitter chose:
**registration** and the **magic link**. Those are the spam-relay vector: an
attacker who cannot read the inbox can still make the server mail anyone, at
your domain's reputation.

Password login is deliberately **not** guarded. A captcha on every routine
sign-in is friction for returning players, and the credentials are their own
proof. Both forms already carry a per-IP rate limit; the captcha adds cover
against distributed abuse, where a botnet stays under the per-IP limit by
spreading itself across thousands of addresses.

**Game clients are unaffected.** The captcha guards the browser forms only;
`POST /api/v1/register` and device login take none, so turning it on cannot
break a shipped Godot or JS client. The API sign-up has the auth rate limit.

### Setup

Create a widget at
[dash.cloudflare.com](https://dash.cloudflare.com/?to=/:account/turnstile)
(free, no request cap, no card) and set:

```bash
GAMEND_CAPTCHA_ENABLED=true
GAMEND_CAPTCHA_SITE_KEY=0x4AAA...
GAMEND_CAPTCHA_SECRET_KEY=0x4AAA...
```

Development and test need none of it: with the keys unset the server falls back
to Cloudflare's published dummy pair, which passes on any host including
localhost. That keeps the widget on the page in development, so a form that only
breaks with a captcha in front of it breaks on your machine rather than in
production. To exercise the failure path, set `GAMEND_CAPTCHA_SECRET_KEY` to the
always-fails dummy `2x0000000000000000000000000000000AA`.

### Behaviour

- **Verification fails closed.** If Cloudflare cannot be reached, the submission
  is rejected rather than allowed through. Treating an unreachable verifier as a
  pass would let anyone able to sit between the server and Cloudflare switch the
  protection off, which is exactly the attacker.
- **Tokens are single-use** and expire after five minutes. A rejected submission
  resets the widget automatically, so the player can retry without reloading.
- **The Content-Security-Policy widens only while the captcha is enabled**, and
  only by naming `challenges.cloudflare.com` in `script-src` and `frame-src`. A
  deployment that never turns it on keeps the strict policy untouched.

Self-hosting behind a proxy that blocks Cloudflare, or deploying somewhere
Turnstile is unreachable, means leaving this off and relying on the rate limits.

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`Gamend.Accounts`](https://docs.gamend.org/Gamend.Accounts.html) - the functions a plugin calls, with their
  signatures and docs.
