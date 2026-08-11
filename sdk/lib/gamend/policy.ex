defmodule Gamend.Policy do
  @moduledoc ~S"""
  One question — "may this user do this to this thing?" — asked the same way
  everywhere.

  Gamend has four owners: a lobby's host, a lobby's pinned WebRTC host, a
  group's admins and a party's leader. Each context decides its own rule and
  keeps deciding it; this module does not own authority, it only routes to the
  context that does:

      Policy.can?(user, :manage, lobby)   # -> Lobbies.can_manage_lobby?/2
      Policy.can?(user, :manage, group)   # -> Groups.can_manage_group?/2
      Policy.can?(user, :manage, party)   # -> Parties.can_manage_party?/2

  A caller that holds a resource but does not know its type — an admin screen,
  a hook, a serializer — can ask without a `case` per resource, and the answer
  comes from the context that owns the rule rather than from a copy of it.

  ## Actions

    * `:view` — read the resource's details. Lobbies only; groups and parties
      have no hidden state to gate yet.
    * `:manage` — everything an owner does: edit, kick, moderate, and for a
      lobby move its `state`. Gamend does not split these, and this module
      will not invent a split it cannot enforce.

  An unknown action or a resource with no rule is `false`, never an error: a
  policy that raises turns a missing case into a 500 instead of a 403.


  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the Gamend.
  """

  @type resource() ::
          Gamend.Lobbies.Lobby.t() | Gamend.Groups.Group.t() | Gamend.Parties.Party.t()
  @type action() :: :view | :manage

  @doc ~S"""
    Whether `user` may perform `action` on `resource`.
    
    `nil` for an anonymous caller. Only `:view` on a public lobby is ever true
    for one.
    
  """
  @spec can?(Gamend.Accounts.User.t() | nil, action(), resource() | nil) :: boolean()
  def can?(_user, _arg2, _lobby) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Policy.can?/3 is a stub - only available at runtime on Gamend"
    end
  end
end
