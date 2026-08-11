defmodule Gamend.Policy do
  @moduledoc """
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
  """

  alias Gamend.Accounts.User
  alias Gamend.Groups
  alias Gamend.Groups.Group
  alias Gamend.Lobbies
  alias Gamend.Lobbies.Lobby
  alias Gamend.Parties
  alias Gamend.Parties.Party

  @type action :: :view | :manage
  @type resource :: Lobby.t() | Group.t() | Party.t()

  @doc """
  Whether `user` may perform `action` on `resource`.

  `nil` for an anonymous caller. Only `:view` on a public lobby is ever true
  for one.
  """
  @spec can?(User.t() | nil, action(), resource() | nil) :: boolean()
  def can?(user, :view, %Lobby{} = lobby), do: Lobbies.can_view_lobby?(user, lobby)
  def can?(user, :manage, %Lobby{} = lobby), do: Lobbies.can_manage_lobby?(user, lobby)
  def can?(user, :manage, %Group{} = group), do: Groups.can_manage_group?(user, group)
  def can?(user, :manage, %Party{} = party), do: Parties.can_manage_party?(user, party)
  def can?(_user, _action, _resource), do: false
end
