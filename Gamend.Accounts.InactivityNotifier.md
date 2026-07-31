# `Gamend.Accounts.InactivityNotifier`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/inactivity_notifier.ex#L1)

Warns a user their account is about to be deleted for inactivity.

`retention_warned_at` is stamped **after** a successful send, not at enqueue:
an un-warned account is one the sweep refuses to delete, so a mail outage
postpones a deletion rather than performing a silent one.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
