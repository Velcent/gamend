# Published baselines

One summary per (cell, commit) that was quoted somewhere — a blog post, a PR,
a decision about hardware. Everything else stays in `results/`, which is
gitignored.

The point of committing these is that a number in a blog post should be
reproducible: the file records the machine, the database, the VU count and the
duration that produced it, and `report.mjs --diff` can put a later run next to
it.

```sh
node report.mjs --diff baselines/B results
```

## Runs

- [2026-08-19-macbook-air-m1.md](2026-08-19-macbook-air-m1.md) — the first full
  run of the harness. One laptop, so a starting point rather than a capacity
  figure, but it is where the `MIX_ENV=prod` trap, the SQLite pool fix and the
  per-socket memory question were all found.
