defmodule Gamend.QuestsRepeatCounterTest do
  @moduledoc """
  A `repeat` quest is one definition and one row that re-arms forever, so
  nothing about it says which run the player is on. `%{n}` in the title is how
  it does: the card reads "Treasures x 1", then "Treasures x 2".

  The substitution has to happen where a definition meets a player's row —
  writing the number into the stored title would show every player the same
  one — which is what these pin.
  """
  use ExUnit.Case, async: true

  alias Gamend.Quests
  alias Gamend.Quests.Quest
  alias Gamend.Quests.QuestProgress

  defp repeat(title, description \\ "d") do
    %Quest{reset: "repeat", title: title, description: description}
  end

  defp progress(claim_count, status \\ "active") do
    %QuestProgress{claim_count: claim_count, status: status}
  end

  test "no row yet reads as the first run" do
    assert Quests.resolve_counter(repeat("Treasures x %{n}"), nil).title == "Treasures x 1"
  end

  test "an unclaimed row is the run in progress" do
    assert Quests.resolve_counter(repeat("Treasures x %{n}"), progress(0)).title ==
             "Treasures x 1"

    assert Quests.resolve_counter(repeat("Treasures x %{n}"), progress(3)).title ==
             "Treasures x 4"
  end

  test "a claimed row keeps the number of the run just finished" do
    # The card must not renumber itself under the player between completing and
    # claiming — they claimed "Treasures x 1", so that is what it says until it
    # re-arms.
    assert Quests.resolve_counter(repeat("Treasures x %{n}"), progress(1, "claimed")).title ==
             "Treasures x 1"

    assert Quests.resolve_counter(repeat("Treasures x %{n}"), progress(4, "claimed")).title ==
             "Treasures x 4"
  end

  test "a claimed row that somehow never counted still reads as run 1, never 0" do
    assert Quests.resolve_counter(repeat("Treasures x %{n}"), progress(0, "claimed")).title ==
             "Treasures x 1"
  end

  test "a nil claim_count is treated as no claims" do
    assert Quests.resolve_counter(repeat("Treasures x %{n}"), progress(nil)).title ==
             "Treasures x 1"
  end

  test "the description takes the counter too" do
    quest = repeat("Treasures x %{n}", "Find treasure number %{n}.")
    resolved = Quests.resolve_counter(quest, progress(2))

    assert resolved.title == "Treasures x 3"
    assert resolved.description == "Find treasure number 3."
  end

  test "a repeat quest without the placeholder is untouched" do
    quest = repeat("Find the treasure")
    assert Quests.resolve_counter(quest, progress(7)) == quest
  end

  test "a non-repeat quest is untouched even if it carries the placeholder" do
    # Daily and never quests get a fresh row per period, so a repetition count
    # would be meaningless — the placeholder is not theirs to use.
    for reset <- ["never", "daily", "weekly"] do
      quest = %Quest{reset: reset, title: "Words x %{n}", description: "d"}
      assert Quests.resolve_counter(quest, progress(9)) == quest
    end
  end
end
