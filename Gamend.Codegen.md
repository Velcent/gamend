# `Gamend.Codegen`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/codegen.ex#L1)

Support for the `mix` tasks that write generated files into the repo.

Four of them — `gamend.settings.guide`, `gamend.settings.env_example`,
`gamend.content.extract`, `gamend.theme.extract` — follow the same shape:
render the file from the source of truth, write it in the normal run, and in
`--check` mode fail if what is on disk differs. They each had their own copy
of the comparison, identical but for the task name in the message, and two of
them carried the same PO quoting rules.

# `check!`

```elixir
@spec check!(Path.t(), iodata(), String.t()) :: :ok
```

Fails the task unless `path` already holds exactly `generated`.

`task` is named in the failure so the reader is told how to fix it.

# `quote_po`

```elixir
@spec quote_po(String.t()) :: String.t()
```

Quotes a string as a PO `msgid`/`msgstr` value.

A value with no newline is one quoted string. A multi-line one becomes the
empty string followed by one quoted line each, with `\n` at the end of every
line but the last — the form gettext tools write, and the only form some of
them will read back.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
