defmodule GamendWeb.Realtime do
  @moduledoc """
  Tuning for outbound realtime state updates.
  """

  use Gamend.Settings.Provider,
    app: :gamend_web,
    group: :realtime,
    label: "Realtime"

  # Each message costs ~76 bytes of WebSocket/TLS/TCP/IP headers before any
  # payload, so coalescing a burst saves more than shrinking payloads does.
  setting(:debounce_ms, :integer,
    default: 0,
    doc:
      "Hold outbound state updates this long and push only the latest per object. 0 pushes immediately."
  )

  # Both pools shard by topic. The defaults keep a single-node deployment
  # exactly as it was; raising them spreads PubSub dispatch and presence
  # replication across schedulers, which is what a five-figure socket count
  # needs. `presence_pool_size` must be identical on every node in a cluster
  # (Phoenix.Tracker syncs shard-to-shard), so change it with a full restart,
  # never a rolling one.
  setting(:pubsub_pool_size, :integer,
    default: 1,
    doc: "Phoenix.PubSub shards. Raise on nodes holding many thousands of sockets."
  )

  setting(:presence_pool_size, :integer,
    default: 1,
    doc:
      "Phoenix.Presence tracker shards. Must match on every node in a cluster; needs a full restart to change."
  )

  # The dominant per-connection cost, and it is an operating-system default
  # rather than anything this app chose. Left alone, the kernel sizes a
  # connection's receive buffer for bulk transfer — measured at ~470 KB on
  # macOS — and the Erlang inet driver sizes its own buffer to match, which
  # showed up as ~105 KB of binary memory per idle socket, two thirds of what a
  # connected player costs.
  #
  # A game exchanging small JSON or protobuf frames never needs that. 32 KB is
  # comfortably above the 16 KB a large lobby state push occupies while leaving
  # room for a burst, and small enough that socket density stops being decided
  # by the kernel's idea of a good download.
  #
  # Raise it if a game sends genuinely large frames (`max_frame_size` is 128 KB);
  # a value under 8 KB starts to cost throughput on anything bulky.
  setting(:socket_buffer_kb, :integer,
    default: 32,
    doc:
      "Per-connection socket buffer in KB (buffer/recbuf/sndbuf). Lower means more sockets per GB."
  )
end
