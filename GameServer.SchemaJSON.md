# `GameServer.SchemaJSON`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/game_server/schema_json.ex#L1)

JSON encoding for Ecto schemas under the API's null policy: string fields
encode as `""` when nil and map fields as `%{}` — game clients (Godot in
particular) choke on `null` where they expect a string. Datetimes, numbers
and booleans keep `null`, where absence is semantic.

Used from a hand-written `Jason.Encoder` impl instead of `@derive`:

    defimpl Jason.Encoder, for: MySchema do
      def encode(struct, opts) do
        GameServer.SchemaJSON.encode(struct, [:id, :title, :icon_url], opts)
      end
    end

# `encode`

Encode `fields` of `struct`, coalescing nil strings/maps.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
