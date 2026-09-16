defmodule Gamend.UnknownUserFkTest do
  @moduledoc """
  Writing a row that points at a user who does not exist.

  These all used to raise `Ecto.ConstraintError`, so an admin request naming a
  stale id — or a plugin passing one — came back 500. The schemas did declare
  `foreign_key_constraint(:user_id)`, but SQLite (the default adapter) does not
  report *which* constraint an INSERT violated, so Ecto cannot match the
  declaration and raises instead of returning a changeset. The adapter's own
  docs say `foreign_key_constraint/3` "may not work at all" there.

  The contexts check first now. The constraint stays declared: it is still the
  thing that makes the row impossible, and on Postgres it still reports.
  """
  use Gamend.DataCase, async: false

  alias Gamend.Economy
  alias Gamend.Inventory
  alias Gamend.Leaderboards

  setup do
    {:ok, board} =
      Leaderboards.create_leaderboard(%{
        "slug" => "unknown_user_#{System.unique_integer([:positive])}",
        "title" => "Unknown User Test"
      })

    %{board: board, ghost: Ecto.UUID.generate()}
  end

  describe "an id that belongs to no account" do
    test "submitting a score answers instead of raising", %{board: board, ghost: ghost} do
      assert Leaderboards.submit_score(board.id, ghost, 10) == {:error, :user_not_found}
    end

    test "granting and spending currency answer instead of raising", %{ghost: ghost} do
      assert Economy.grant(ghost, "gold", 10) == {:error, :user_not_found}
      assert Economy.spend(ghost, "gold", 10) == {:error, :user_not_found}
    end

    test "granting and consuming items answer instead of raising", %{ghost: ghost} do
      assert Inventory.grant_item(ghost, "sword", 1) == {:error, :user_not_found}
      assert Inventory.consume_item(ghost, "sword", 1) == {:error, :user_not_found}
    end
  end

  describe "a malformed id" do
    test "is not found rather than an Ecto.Query.CastError", %{board: board} do
      assert Leaderboards.submit_score(board.id, "not-a-uuid", 10) == {:error, :user_not_found}
      assert Economy.grant("not-a-uuid", "gold", 10) == {:error, :user_not_found}
    end
  end

  describe "a real user is unaffected" do
    test "the happy paths still write", %{board: board} do
      user = Gamend.AccountsFixtures.user_fixture()

      assert {:ok, record} = Leaderboards.submit_score(board.id, user.id, 42)
      assert record.score == 42

      assert {:ok, 10} = Economy.grant(user.id, "gold", 10)
      assert {:ok, 1} = Inventory.grant_item(user.id, "sword", 1)
    end
  end
end
