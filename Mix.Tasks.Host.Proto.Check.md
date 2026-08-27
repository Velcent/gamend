# `mix host.proto.check`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/mix/tasks/host.proto.check.ex#L1)

Check that registered protobuf schemas actually match the JSON they encode.

A protobuf schema here is an opt-in wire optimisation over a value that is
still stored and sent as JSON. The encoder is deliberately safe: a value the
schema does not fully describe is sent as JSON instead, so a schema can never
drop or corrupt data. The cost of that safety is silence — a schema missing
one field is not an error anywhere, it simply never encodes, and the
optimisation you think you shipped is inert.

That has happened twice in this codebase and neither was noticed by a test:

  * `Progress` listed neither `words_total` nor several other keys the
    canonical shape always carries, so *every* player's progress fell back to
    JSON — the protobuf path had never encoded a single row.
  * A hand-written Godot decoder omitted `awaiting_continue`, so a paid
    continue offer was decoded away and players sat in a paused game with no
    prompt and no way on.

This task is the check that would have caught both, run against real data:
for every registered schema it takes the values actually stored under those
keys and reports which of them fail to encode, and why.

## Usage

    mix host.proto.check                     # every registered schema
    mix host.proto.check --limit 200         # rows sampled per key (default 50)
    mix host.proto.check --key progress      # one key or entity only

It covers both places a schema is applied to stored data: KV entry values
(registered explicitly via `kv_schemas/0`) and user/lobby/group/party
metadata (registered by naming a `UserMeta`/`LobbyMeta`/`GroupMeta`/
`PartyMeta` message). It also prints, without failing, what is NOT typed —
the KV keys, metadata entities and hooks still going out as JSON — because
nothing else in the system reports that either.

What it cannot sample is anything that is never stored — a typed hook's
request or reply, most of all. Capture one real payload and name its module;
this is also the form to hand someone who reports "protobuf is not working":

    mix host.proto.check --json captured.json --message MyGame.V1.HelloReply

Exit status is 1 when any sampled value fails to encode, so it can gate CI.

## What a failure means

`unknown keys` are keys present in the data that the schema has no field for.
They are the usual cause: add the field to the `.proto`, regenerate with
`mix host.proto.gen`, and re-run. `encode errors` are keys the schema knows
but whose *type* disagrees, which is the same class of bug one level down.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
