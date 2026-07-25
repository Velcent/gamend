# `GameServer.Mail`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/game_server/mail.ex#L1)

Outbound email transport.

With no password set, `GameServer.Mailer` uses Swoosh's local adapter and
mail lands in the in-browser mailbox at `/dev/mailbox` — the whole flow works
with zero credentials. Setting a password means you intended to send real
mail, so the relay and username are expected alongside it.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
