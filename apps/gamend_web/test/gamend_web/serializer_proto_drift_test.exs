defmodule GamendWeb.SerializerProtoDriftTest do
  @moduledoc """
  Keeps the protobuf wire contract honest against the JSON one: every key a
  `GamendWeb.Serializers` payload carries must be representable in the
  corresponding proto message (per the documented transforms — `*_at` becomes
  `*_at_ms`, `metadata` becomes `metadata_json`/`metadata_pb`).

  Grep-style like RealtimeEventsDriftTest, because the drift it hunts is
  structural: `Lobby.state` was missing for months and every protobuf client
  silently read no lobby state at all — nothing crashed, the field just never
  arrived. Payloads assembled outside Serializers (user presence payloads,
  member events) are covered by the channel tests instead.
  """
  use ExUnit.Case, async: true

  @serializers_src File.read!(Path.expand("../../lib/gamend_web/serializers.ex", __DIR__))
  @proto_src File.read!(Path.expand("../../../../proto/gamend_realtime.proto", __DIR__))

  @pairs [
    {"serialize_lobby", "Lobby"},
    {"serialize_group", "Group"},
    {"serialize_party", "Party"},
    {"serialize_notification", "Notification"},
    {"serialize_chat_message", "ChatMessage"},
    {"serialize_quest_progress", "QuestProgress"},
    {"serialize_ready_check", "ReadyCheckState"},
    {"serialize_ready_participant", "ReadyCheckParticipant"}
  ]

  test "every Serializers payload key is representable in its proto message" do
    keys = keys_by_function()
    fields = fields_by_message()

    problems =
      for {func, message} <- @pairs,
          key <- Map.fetch!(keys, func),
          not representable?(key, Map.fetch!(fields, message)) do
        "#{func} sends \"#{key}\" but proto message #{message} cannot carry it"
      end

    assert problems == [],
           Enum.join(problems, "\n") <>
             "\n— add the field to proto/gamend_realtime.proto (and regenerate " <>
             "both the Elixir module and the Godot bindings via mix host.proto.gen), " <>
             "or it silently never reaches protobuf clients"
  end

  # A JSON key is representable when the proto has it verbatim or through the
  # documented transforms.
  defp representable?(key, fields) do
    key in fields or
      "#{key}_ms" in fields or
      (key == "metadata" and "metadata_json" in fields)
  end

  # Map keys per serializer function, across all its clauses: `key: value`
  # literals plus bare `:key` atoms threaded through maybe_put/Map.put.
  defp keys_by_function do
    bounds =
      Regex.scan(~r/^  defp? (\w+)/m, @serializers_src, return: :index)
      |> Enum.map(fn [{start, _}, {ns, nl}] ->
        {binary_part(@serializers_src, ns, nl), start}
      end)

    starts = Enum.map(bounds, &elem(&1, 1)) ++ [byte_size(@serializers_src)]

    bounds
    |> Enum.zip(tl(starts))
    |> Enum.reduce(%{}, fn {{name, start}, next}, acc ->
      body = binary_part(@serializers_src, start, next - start)

      keys =
        (Regex.scan(~r/^\s+(\w+): /m, body) ++ Regex.scan(~r/:(\w+),$/m, body))
        |> Enum.map(fn [_, k] -> k end)

      Map.update(acc, name, MapSet.new(keys), &MapSet.union(&1, MapSet.new(keys)))
    end)
  end

  defp fields_by_message do
    Regex.scan(~r/message (\w+) \{(.*?)\n\}/s, @proto_src)
    |> Map.new(fn [_, name, body] ->
      fields =
        Regex.scan(~r/ (\w+) = \d+;/, body)
        |> Enum.map(fn [_, f] -> f end)
        |> MapSet.new()

      {name, fields}
    end)
  end
end
