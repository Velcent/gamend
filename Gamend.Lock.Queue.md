# `Gamend.Lock.Queue`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/lock/queue.ex#L1)

The waiting line behind `Gamend.Lock.Local`: per key, one holder and the
callers after it, served in the order they asked.

Partitioned by key (`PartitionSupervisor`, one partition per scheduler), so
keys spread over several processes and one busy key does not hold up the
rest. Each partition monitors the holder and every waiter: a holder that dies
passes the key on, and a waiter that dies leaves the line.

Callers use `Gamend.Lock.Local`, which keeps the reentrancy, not this.

# `acquire`

```elixir
@spec acquire(term()) :: :ok
```

Blocks until the calling process holds `key`.

# `release`

```elixir
@spec release(term()) :: :ok
```

Hands `key` to the next caller in line. A key the caller does not hold is ignored.

# `running?`

```elixir
@spec running?() :: boolean()
```

Whether the partitions are running (they start with the host's tree).

---

*Consult [api-reference.md](api-reference.md) for complete listing*
