defmodule GameServer.LockTest do
  @moduledoc """
  `Lock.serialize/3` on whichever adapter the suite is running.

  The interesting part is not that it serializes — an immediate transaction does
  that on its own — but that it does so *per key*, and for sections that never
  touch the database.
  """
  use GameServer.DataCase, async: false

  alias GameServer.Lock

  setup do
    table = :ets.new(:lock_test, [:public, :set])
    on_exit(fn -> if :ets.info(table) != :undefined, do: :ets.delete(table) end)
    %{table: table}
  end

  defp bump(table, key, delta) do
    :ets.update_counter(table, key, delta, {key, 0})
  end

  test "one caller at a time holds a given key", %{table: table} do
    :ets.insert(table, {:peak, 0})

    tasks =
      for _ <- 1..25 do
        Task.async(fn ->
          Lock.serialize(:lobby, "same-key", fn ->
            inside = bump(table, :inside, 1)
            if inside > bump(table, :peak, 0), do: :ets.insert(table, {:peak, inside})
            Process.sleep(2)
            bump(table, :inside, -1)
            :ok
          end)
        end)
      end

    Enum.each(tasks, &Task.await(&1, 30_000))

    assert [{:peak, 1}] = :ets.lookup(table, :peak)
    assert [{:inside, 0}] = :ets.lookup(table, :inside)
  end

  # Don't assert per-key *parallelism* here: `DataCase` shares one sandbox
  # connection across processes, so no two transactions can overlap whatever the
  # lock does, and SQLite's single writer bounds it in production anyway.
  test "different keys do not interfere" do
    tasks =
      for i <- 1..10 do
        Task.async(fn -> Lock.serialize(:lobby, "key-#{i}", fn -> i end) end)
      end

    results = Enum.map(tasks, &Task.await(&1, 30_000))
    assert Enum.sort(results) == Enum.sort(for i <- 1..10, do: {:ok, i})
  end

  test "namespaces are distinct keys" do
    assert {:ok, :a} = Lock.serialize(:lobby, "shared-id", fn -> :a end)
    assert {:ok, :b} = Lock.serialize(:group, "shared-id", fn -> :b end)
    assert {:ok, :c} = Lock.serialize("ad_hoc", "shared-id", fn -> :c end)
  end

  # The regression that broke the suite when the mutex was added: an inner
  # `serialize/3` on a different key must not wait on a mutex while holding the
  # write lock, or it inverts lock order against whoever holds that mutex.
  test "a nested acquisition on a different key does not deadlock" do
    task =
      Task.async(fn ->
        Lock.serialize(:tournaments_tick, "global", fn ->
          Lock.serialize(:tournament_draw, "some-tournament", fn -> :inner end)
        end)
      end)

    assert {:ok, {:ok, :inner}} = Task.await(task, 15_000)
  end

  test "nested acquisition of the same key in one process does not deadlock" do
    assert {:ok, {:ok, :inner}} =
             Lock.serialize(:lobby, "reentrant", fn ->
               Lock.serialize(:lobby, "reentrant", fn -> :inner end)
             end)
  end

  test "a critical section that never touches the database is still exclusive", %{table: table} do
    :ets.insert(table, {:peak, 0})

    tasks =
      for _ <- 1..20 do
        Task.async(fn ->
          Lock.serialize("ets_only", "shared", fn ->
            inside = bump(table, :inside, 1)
            if inside > bump(table, :peak, 0), do: :ets.insert(table, {:peak, inside})
            Process.sleep(1)
            bump(table, :inside, -1)
            :no_repo_access
          end)
        end)
      end

    Enum.each(tasks, &Task.await(&1, 30_000))

    assert [{:peak, 1}] = :ets.lookup(table, :peak)
  end

  # `:global` releases on holder death, so a crash must not wedge the key.
  test "a crash inside the section releases the key" do
    {pid, ref} =
      spawn_monitor(fn -> Lock.serialize(:lobby, "crashy", fn -> raise "boom" end) end)

    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 10_000

    assert {:ok, :recovered} = Lock.serialize(:lobby, "crashy", fn -> :recovered end)
  end
end
