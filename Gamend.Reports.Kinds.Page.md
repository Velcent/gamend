# `Gamend.Reports.Kinds.Page`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/reports/kinds/page.ex#L1)

The built-in report kind: something on a page is broken or looks wrong.

The subject is the page's path (query kept, fragment dropped), and the
duplicates key is the path alone. A full URL is accepted and cut down to its
path, so a reporter can paste the address bar; a URL on another site is
kept as typed, since the report may well be about a link that leads there.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
