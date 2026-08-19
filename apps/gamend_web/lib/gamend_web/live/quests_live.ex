defmodule GamendWeb.QuestsLive do
  @moduledoc """
  Public-facing quests page.

  Anonymous users browse the catalog (hidden quests appear as teasers).
  Logged-in users see their progress per reset period, can filter by category
  and status, and claim completed quests.
  """
  use GamendWeb, :live_view

  alias Gamend.Accounts.Scope
  alias Gamend.Quests
  alias Gamend.Quests.Quest
  alias GamendWeb.ContentText
  alias GamendWeb.Plugs.FeatureGate

  @page_size 50

  @status_filters [nil, "in_progress", "claimable", "done"]

  @impl true
  def mount(_params, _session, socket) do
    unless FeatureGate.enabled?(:list_quests) do
      raise GamendWeb.NotFoundError
    end

    user = get_user(socket)

    if connected?(socket) do
      Quests.subscribe_quests()
      if user, do: Phoenix.PubSub.subscribe(Gamend.PubSub, "user:#{user.id}")
    end

    socket =
      socket
      |> assign(:locale, Gettext.get_locale(GamendWeb.Gettext))
      |> assign(:page_title, gettext("Quests"))
      |> assign(:page, 1)
      |> assign(:page_size, @page_size)
      |> assign(:category, nil)
      |> assign(:group, nil)
      |> assign(:status, nil)
      |> assign(:chain, nil)
      |> assign(:chain_focus, nil)
      |> load_quests()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("category", %{"category" => category}, socket) do
    category = if category == "", do: nil, else: category

    {:noreply,
     socket
     |> assign(:category, if(category in socket.assigns.categories, do: category))
     |> assign(:page, 1)
     |> load_quests()}
  end

  def handle_event("status", %{"status" => status}, socket) do
    status = if status == "", do: nil, else: status

    {:noreply,
     socket
     |> assign(:status, if(status in @status_filters, do: status))
     |> assign(:page, 1)
     |> load_quests()}
  end

  def handle_event("claim", %{"key" => key}, socket) do
    case get_user(socket) do
      nil ->
        {:noreply, socket}

      user ->
        case Quests.claim(user.id, key) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Rewards claimed!"))
             |> load_quests()}

          {:error, :already_claimed} ->
            {:noreply, socket |> put_flash(:error, gettext("Already claimed.")) |> load_quests()}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, gettext("Could not claim this quest."))}
        end
    end
  end

  def handle_event("show_chain", %{"key" => key}, socket) do
    user = get_user(socket)

    case Quests.chain(user && user.id, key) do
      entries when length(entries) > 1 ->
        {:noreply,
         socket
         |> assign(:chain, ContentText.translate(entries))
         |> assign(:chain_focus, key)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("close_chain", _params, socket) do
    {:noreply, socket |> assign(:chain, nil) |> assign(:chain_focus, nil)}
  end

  def handle_event("show_group", %{"group" => group_key}, socket) do
    user = get_user(socket)

    case Quests.group(user && user.id, group_key) do
      [] -> {:noreply, socket}
      members -> {:noreply, assign(socket, :group, ContentText.translate(members))}
    end
  end

  def handle_event("close_group", _params, socket), do: {:noreply, assign(socket, :group, nil)}

  def handle_event("chain_noop", _params, socket), do: {:noreply, socket}

  def handle_event("prev_page", _params, socket) do
    {:noreply,
     socket
     |> assign(:page, max(1, socket.assigns.page - 1))
     |> load_quests()}
  end

  def handle_event("next_page", _params, socket) do
    {:noreply,
     socket
     |> assign(:page, socket.assigns.page + 1)
     |> load_quests()}
  end

  def handle_event("page_size", %{"size" => size}, socket) do
    size = size |> String.to_integer() |> min(200) |> max(24)

    {:noreply,
     socket
     |> assign(:page_size, size)
     |> assign(:page, 1)
     |> load_quests()}
  end

  @impl true
  def handle_info({:quests_changed}, socket) do
    {:noreply, load_quests(socket)}
  end

  def handle_info({event, _payload}, socket)
      when event in [:quest_progress, :quest_completed, :quest_claimed] do
    {:noreply, load_quests(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp get_user(socket), do: Scope.user(socket.assigns[:current_scope])

  defp load_quests(socket) do
    user = get_user(socket)
    page = socket.assigns.page
    page_size = socket.assigns.page_size
    category = socket.assigns.category
    status = socket.assigns.status
    active = Quests.active_quests()

    {entries, total_count, claimable} =
      if user do
        opts = [page: page, page_size: page_size, category: category, status: status]

        {Quests.list_user_quests(user.id, opts),
         Quests.count_user_quests(user.id, category: category, status: status),
         Quests.claimable_count(user.id)}
      else
        {catalog_entries, total} = anonymous_catalog(active, category, page, page_size)
        {catalog_entries, total, 0}
      end

    entries = entries |> ContentText.translate() |> lock_labels(user)

    socket
    |> assign(:categories, [nil | Quests.visible_categories(user && user.id)])
    # Titles and descriptions are stored in the source language; translate on
    # the way to the page. Admin pages deliberately show the stored string.
    |> assign(:entries, entries)
    |> assign(:total_count, total_count)
    |> assign(:total_pages, max(ceil(total_count / page_size), 1))
    |> assign(:claimable_count, claimable - locked_claimable(entries))
    |> assign(:chain_positions, chain_positions(active))
    |> assign(:now, DateTime.utc_now(:second))
    |> refresh_chain()
  end

  # The host's reason this viewer cannot claim this quest yet, resolved once per
  # entry so the card stays a pure render. nil for everyone who can claim it,
  # and for a host that registers no filter.
  #
  # Signed-in only, like the status badge beside it: a lock is a fact about an
  # account, and a visitor with none has nothing it could be about. The catalog
  # a guest (or a crawler) reads is the quests, not their standing in them.
  defp lock_labels(entries, nil), do: entries

  defp lock_labels(entries, user) do
    Enum.map(entries, &Map.put(&1, :lock_label, Quests.host_lock_label(&1.quest, user.id)))
  end

  # "N quests ready to claim" must mean N buttons: a locked quest is finished
  # and offers nothing, so counting it sends the reader hunting for a button
  # that is deliberately not there.
  defp locked_claimable(entries) do
    Enum.count(entries, &(&1.claimable and locked?(&1)))
  end

  defp locked?(entry), do: is_binary(Map.get(entry, :lock_label))

  # Keep an open chain modal current when quest data changes underneath it
  # (a claim, a PubSub progress event). Closes it if the chain dissolved.
  defp refresh_chain(socket) do
    case socket.assigns[:chain_focus] do
      nil ->
        socket

      key ->
        user = get_user(socket)

        case Quests.chain(user && user.id, key) do
          entries when length(entries) > 1 -> assign(socket, :chain, entries)
          _ -> socket |> assign(:chain, nil) |> assign(:chain_focus, nil)
        end
    end
  end

  # Position of each chained quest within its prerequisite line, as
  # {position, total} — e.g. tier 3 of 7. Quests without prerequisite links
  # get no entry.
  #
  # Cycles are cut by remembering what has been walked, not by a hop cap. A cap
  # cannot tell a malformed cycle from a genuinely long chain: at 20 hops the
  # 52-unit course reported every unit as "1 of 21", silently, because the walk
  # bottomed out rather than reaching the end.
  defp chain_positions(quests) do
    prereq_by_key = Map.new(quests, &{&1.key, &1.prerequisite_quest_key})

    depths =
      Map.new(prereq_by_key, fn {key, _} ->
        {key, chain_depth(key, prereq_by_key, %{})}
      end)

    totals =
      Enum.reduce(depths, %{}, fn {key, depth}, acc ->
        root = chain_root(key, prereq_by_key, %{})
        Map.update(acc, root, depth + 1, &max(&1, depth + 1))
      end)

    depths
    |> Enum.map(fn {key, depth} ->
      {key, {depth + 1, Map.get(totals, chain_root(key, prereq_by_key, %{}), depth + 1)}}
    end)
    |> Enum.filter(fn {_key, {_pos, total}} -> total > 1 end)
    |> Map.new()
  end

  # `seen` is a plain map, not a MapSet: dialyzer strips the opacity off a
  # MapSet built and consumed inside one recursion and then reports the
  # MapSet.member?/2 call as a type mismatch.
  defp chain_depth(key, prereq_by_key, seen) do
    if Map.has_key?(seen, key) do
      0
    else
      case Map.get(prereq_by_key, key) do
        nil -> 0
        prereq -> 1 + chain_depth(prereq, prereq_by_key, Map.put(seen, key, true))
      end
    end
  end

  defp chain_root(key, prereq_by_key, seen) do
    if Map.has_key?(seen, key) do
      key
    else
      case Map.get(prereq_by_key, key) do
        nil -> key
        prereq -> chain_root(prereq, prereq_by_key, Map.put(seen, key, true))
      end
    end
  end

  defp anonymous_catalog(active, category, page, page_size) do
    now = DateTime.utc_now(:second)

    # Chains collapse to their first tier: with no progress every later tier
    # is locked anyway, and listing them would show one chain as N cards.
    visible =
      Enum.filter(active, fn q ->
        category in [nil, q.category] and within_window?(q, now) and
          is_nil(q.prerequisite_quest_key)
      end)

    collapsed = collapse_groups_for_catalog(visible)

    entries =
      collapsed
      |> Enum.drop((page - 1) * page_size)
      |> Enum.take(page_size)
      |> Enum.map(fn {quest, size} ->
        %{quest: quest, progress: nil, claimable: false, group_size: size}
      end)

    {entries, length(collapsed)}
  end

  # `{quest, group_size}` in first-appearance order. Nobody is signed in, so
  # there is no progress to rank members by — the first one stands for the group.
  defp collapse_groups_for_catalog(quests) do
    by_key = Enum.group_by(quests, & &1.group_key)

    quests
    |> Enum.map(& &1.group_key)
    |> Enum.uniq()
    |> Enum.flat_map(fn
      nil -> Enum.map(Map.get(by_key, nil, []), &{&1, 1})
      key -> [{hd(Map.fetch!(by_key, key)), length(Map.fetch!(by_key, key))}]
    end)
  end

  defp within_window?(quest, now) do
    (is_nil(quest.starts_at) or DateTime.compare(quest.starts_at, now) != :gt) and
      (is_nil(quest.ends_at) or DateTime.compare(quest.ends_at, now) == :gt)
  end

  defp category_label(nil), do: gettext("All")

  # Categories are free-form host labels, so only the first grapheme is
  # upcased — `String.capitalize/1` would downcase the rest and turn "PvP"
  # into "Pvp". Anything beyond that (plurals especially) is the host's to
  # write, since "story" cannot be pluralised mechanically.
  defp category_label(category) do
    case String.next_grapheme(category) do
      {first, rest} -> String.upcase(first) <> rest
      nil -> category
    end
  end

  # A green badge for anything the player has finished, mirroring the Active
  # badge on leaderboards and tournaments; neutral for work still to do.
  defp card_status_class(%{claimable: true}), do: "badge-success"
  defp card_status_class(%{claimed?: true}), do: "badge-success"
  defp card_status_class(%{done?: true}), do: "badge-success"
  defp card_status_class(_assigns), do: "badge-neutral"

  defp card_status_label(%{claimable: true}), do: gettext("Ready to claim")
  defp card_status_label(%{claimed?: true}), do: gettext("Claimed")
  defp card_status_label(%{done?: true}), do: gettext("Completed")
  defp card_status_label(%{progress: %{}}), do: gettext("In progress")
  defp card_status_label(_assigns), do: gettext("Not started")

  # "Daily check-in / Daily / Daily" — the category and the reset cadence often
  # say the same thing, so only show the cadence when it adds something.
  defp same_as_category?(%Quest{category: nil}), do: false

  defp same_as_category?(%Quest{} = quest) do
    String.downcase(to_string(quest.category)) == String.downcase(reset_label(quest))
  end

  defp reset_label(%Quest{reset: "daily"}), do: gettext("Daily")
  defp reset_label(%Quest{reset: "weekly"}), do: gettext("Weekly")
  defp reset_label(%Quest{reset: "monthly"}), do: gettext("Monthly")

  defp reset_label(%Quest{reset: "interval", reset_interval_days: days}),
    do: gettext("Every %{count}d", count: days)

  defp reset_label(_quest), do: ""

  defp status_label(nil), do: gettext("All")
  defp status_label("in_progress"), do: gettext("In Progress")
  defp status_label("claimable"), do: gettext("Claimable")
  defp status_label("done"), do: gettext("Completed")

  # Whichever comes first: the window closing, or the next reset.
  defp time_left(quest, now) do
    [window_left(quest, now), reset_left(quest, now)]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      values -> Enum.min(values)
    end
  end

  defp window_left(%Quest{ends_at: %DateTime{} = ends_at}, now),
    do: max(DateTime.diff(ends_at, now), 0)

  defp window_left(_quest, _now), do: nil

  defp reset_left(%Quest{reset: "never"}, _now), do: nil

  defp reset_left(quest, now) do
    date = DateTime.to_date(now)

    next =
      case quest.reset do
        "daily" -> Date.add(date, 1)
        "weekly" -> Date.add(date, 8 - Date.day_of_week(date))
        "monthly" -> date |> Date.end_of_month() |> Date.add(1)
        "interval" -> Date.add(date, interval_days_left(quest, date))
        _ -> nil
      end

    if next, do: DateTime.diff(DateTime.new!(next, ~T[00:00:00]), now)
  end

  defp interval_days_left(%Quest{reset_interval_days: days}, date)
       when is_integer(days) and days > 0 do
    days - rem(Date.diff(date, ~D[1970-01-01]), days)
  end

  defp interval_days_left(_quest, _date), do: 1

  defp format_duration(seconds) when seconds >= 86_400, do: "#{div(seconds, 86_400)}d"

  defp format_duration(seconds) when seconds >= 3_600,
    do: "#{div(seconds, 3_600)}h #{div(rem(seconds, 3_600), 60)}m"

  defp format_duration(seconds), do: "#{div(seconds, 60)}m"

  defp objective_rows(quest, progress) do
    counts = (progress && progress.objective_progress) || %{}

    quest.objectives
    |> Enum.with_index()
    |> Enum.map(fn {objective, index} ->
      count = counts |> Map.get(Integer.to_string(index), 0) |> min(objective.target)
      %{count: count, target: objective.target}
    end)
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <%!-- Header --%>
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div>
            <h1 class="text-4xl font-black text-base-content/95">
              {gettext("Quests")}
              <span class="text-base-content/70 font-normal">({@total_count})</span>
            </h1>
          </div>

          <%= if @current_scope && Scope.user(@current_scope) do %>
            <div class="flex flex-wrap gap-2">
              <button
                :for={status <- [nil, "in_progress", "claimable", "done"]}
                phx-click="status"
                phx-value-status={status || ""}
                class={[
                  "btn btn-sm",
                  if(@status == status, do: "btn-primary", else: "btn-outline")
                ]}
              >
                {status_label(status)}
                <span :if={status == "claimable" and @claimable_count > 0} class="badge badge-sm">
                  {@claimable_count}
                </span>
              </button>
            </div>
          <% end %>
        </div>

        <%!-- Kind tabs --%>
        <div role="tablist" class="tabs tabs-box w-fit">
          <button
            :for={category <- @categories}
            role="tab"
            phx-click="category"
            phx-value-category={category || ""}
            class={["tab", @category == category && "tab-active"]}
          >
            {category_label(category)}
          </button>
        </div>

        <%!-- Claimable banner --%>
        <%= if @claimable_count > 0 do %>
          <div class="alert alert-success">
            <.icon name="hero-gift" class="w-5 h-5" />
            <span>{gettext("You have %{count} quest(s) ready to claim!", count: @claimable_count)}</span>
          </div>
        <% end %>

        <%!-- Quest grid --%>
        <%= if @entries == [] do %>
          <div class="text-center py-16 text-base-content/70">
            <.icon name="hero-map" class="w-16 h-16 mx-auto mb-4 opacity-30" />
            <p class="text-lg">
              {gettext("No results.")}
            </p>
          </div>
        <% else %>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            <.quest_card
              :for={entry <- @entries}
              entry={entry}
              logged_in={@current_scope != nil && Scope.user(@current_scope) != nil}
              locale={@locale}
              now={@now}
              chain_position={@chain_positions[entry.quest.key]}
              group_size={Map.get(entry, :group_size, 1)}
            />
          </div>
        <% end %>

        <%!-- Pagination --%>
        <div class="flex justify-center items-center pt-4">
          <.pagination
            page={@page}
            total_pages={@total_pages}
            total_count={@total_count}
            page_size={@page_size}
            on_prev="prev_page"
            on_next="next_page"
            on_page_size="page_size"
            page_sizes={[24, 50, 100, 200]}
          />
        </div>

        <.chain_modal :if={@chain} chain={@chain} focus={@chain_focus} locale={@locale} />
        <.group_modal :if={@group} group={@group} />
      </div>
    </Layouts.app>
    """
  end

  # Full prerequisite chain of one quest, shown when a chained card is clicked.
  # This is the only place a player sees tiers ahead of the one they are on —
  # the list itself hides a quest until its prerequisite is done. Hidden quests
  # keep their teaser ("???") until earned, so the chain never spoils them.
  defp chain_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-[60] flex items-center justify-center bg-black/50 p-4"
      phx-click="close_chain"
    >
      <%!-- Inner clicks land on this binding (closest phx-click wins), so they
            don't reach the backdrop's close_chain. --%>
      <div
        class="card bg-base-100 shadow-xl w-full max-w-md max-h-[80vh] overflow-y-auto"
        phx-click="chain_noop"
      >
        <div class="card-body p-5">
          <div class="flex items-center justify-between mb-2">
            <h3 class="font-bold text-lg flex items-center gap-2">
              <.icon name="hero-link" class="w-5 h-5" />
              {gettext("Quest chain")}
            </h3>
            <button phx-click="close_chain" class="btn btn-ghost btn-sm btn-circle" type="button">
              <.icon name="hero-x-mark" class="w-4 h-4" />
            </button>
          </div>

          <ol class="space-y-0">
            <li :for={{entry, index} <- Enum.with_index(@chain)} class="relative">
              <div :if={index > 0} class="ms-[15px] h-4 border-s-2 border-base-300"></div>
              <div class={[
                "flex items-center gap-3 rounded-lg p-2",
                entry.quest.key == @focus && "bg-base-200"
              ]}>
                <div class={[
                  "flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center text-sm font-semibold",
                  chain_tier_class(entry)
                ]}>
                  <%= if entry_done?(entry) do %>
                    <.icon name="hero-check" class="w-4 h-4" />
                  <% else %>
                    {entry.tier}
                  <% end %>
                </div>
                <div class="min-w-0 flex-1">
                  <div class="font-medium text-sm truncate">
                    {entry_title(entry)}
                  </div>
                  <div class="text-xs text-base-content/60">
                    {chain_status_label(entry)}
                  </div>
                </div>
                <%!-- A secret tier must not leak its icon, so it keeps the
                      shared fallback. --%>
                <.entity_icon
                  icon_url={if entry_secret?(entry), do: nil, else: entry.quest.icon_url}
                  type={:quest}
                  class="w-6 h-6 flex-shrink-0"
                />
              </div>
            </li>
          </ol>
        </div>
      </div>
    </div>
    """
  end

  # The members behind the one entry a group collapses into. Flat, not a ladder:
  # every member is live, so unlike the chain modal nothing is numbered or
  # locked. Hidden members keep their teaser here too.
  attr :group, :list, required: true

  defp group_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-[60] flex items-center justify-center bg-black/50 p-4"
      phx-click="close_group"
    >
      <div
        class="card bg-base-100 shadow-xl w-full max-w-md max-h-[80vh] overflow-y-auto"
        phx-click="chain_noop"
      >
        <div class="card-body p-5">
          <div class="flex items-center justify-between mb-2">
            <h3 class="font-bold text-lg flex items-center gap-2">
              <.icon name="hero-rectangle-stack" class="w-5 h-5" />
              {group_modal_title(@group)}
            </h3>
            <button phx-click="close_group" class="btn btn-ghost btn-sm btn-circle" type="button">
              <.icon name="hero-x-mark" class="w-4 h-4" />
            </button>
          </div>

          <ul class="space-y-1">
            <li :for={entry <- @group} class="flex items-center gap-3 rounded-lg p-2">
              <.entity_icon
                icon_url={if entry_secret?(entry), do: nil, else: entry.quest.icon_url}
                type={:quest}
                class="w-6 h-6 flex-shrink-0"
              />
              <div class="min-w-0 flex-1">
                <div class="font-medium text-sm truncate">{entry_title(entry)}</div>
                <div class="text-xs text-base-content/60">{entry_status_label(entry)}</div>
              </div>
              <span class="text-xs text-base-content/60 text-nowrap">
                {group_member_counts(entry)}
              </span>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  defp group_modal_title([%{quest: %Quest{group_title: title}} | _]) when is_binary(title),
    do: title

  defp group_modal_title(_group), do: gettext("Quests")

  # "12 / 250" for the one objective these carry. A member with several would
  # need the card's own breakdown, so it gets no summary rather than a wrong one.
  defp group_member_counts(%{quest: %Quest{objectives: [objective]}, progress: progress} = entry) do
    if entry_secret?(entry) do
      ""
    else
      done =
        case progress do
          %{objective_progress: counts} when is_map(counts) -> Map.get(counts, "0", 0)
          _ -> 0
        end

      "#{done} / #{objective.target}"
    end
  end

  defp group_member_counts(_entry), do: ""

  defp entry_done?(%{progress: progress}),
    do: progress != nil and progress.status in ["completed", "claimed"]

  defp entry_secret?(entry), do: entry.quest.hidden and not entry_done?(entry)

  defp entry_title(entry) do
    if entry_secret?(entry), do: "???", else: entry.quest.title
  end

  defp chain_tier_class(entry) do
    cond do
      entry_done?(entry) -> "bg-success/20 text-success"
      entry.locked -> "bg-base-300 text-base-content/70"
      true -> "bg-primary/20 text-primary"
    end
  end

  # Only chain entries carry `:locked` — a tier waiting on the one before it.
  defp chain_status_label(%{locked: true}), do: gettext("Locked")
  defp chain_status_label(entry), do: entry_status_label(entry)

  defp entry_status_label(entry) do
    cond do
      entry.progress != nil and entry.progress.status == "claimed" -> gettext("Claimed")
      entry.claimable -> gettext("Ready to claim")
      entry_done?(entry) -> gettext("Completed")
      entry.progress != nil -> gettext("In progress")
      true -> gettext("Not started")
    end
  end

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  defp quest_card(assigns) do
    quest = assigns.entry.quest
    progress = assigns.entry.progress
    claimable = assigns.entry.claimable
    done? = progress != nil and progress.status in ["completed", "claimed"]
    claimed? = progress != nil and progress.status == "claimed"
    # Hidden quests stay teasers until earned, the way achievements did.
    secret? = quest.hidden and not done?
    left = time_left(quest, assigns.now)
    # A card standing for more than itself is the group, not the member picked to
    # represent it, so it takes the group's name and opens the whole list.
    grouped? = is_binary(quest.group_key) and assigns.group_size > 1

    assigns =
      assigns
      |> assign(:quest, quest)
      |> assign(:progress, progress)
      |> assign(:claimable, claimable)
      |> assign(:done?, done?)
      |> assign(:claimed?, claimed?)
      |> assign(:left, left)
      |> assign(:secret?, secret?)
      |> assign(:lock_label, Map.get(assigns.entry, :lock_label))
      |> assign(:objective_rows, if(secret?, do: [], else: objective_rows(quest, progress)))
      |> assign(:grouped?, grouped?)
      |> assign(
        :localized_title,
        cond do
          grouped? -> quest.group_title || quest.title
          secret? -> "???"
          true -> quest.title
        end
      )
      |> assign(
        :localized_desc,
        if(secret?, do: gettext("Hidden"), else: quest.description)
      )

    ~H"""
    <.entity_card
      title={@localized_title}
      icon_url={@quest.icon_url}
      type={:quest}
      description={@localized_desc}
      class={[
        (@chain_position || @grouped?) && "cursor-pointer",
        cond do
          @claimable -> "border border-success"
          @done? -> "border border-success/30"
          true -> ""
        end
      ]}
      phx-click={(@grouped? && "show_group") || (@chain_position && "show_chain")}
      phx-value-group={@grouped? && @quest.group_key}
      phx-value-key={not @grouped? && @chain_position && @quest.key}
    >
      <:badges>
        <%!-- Progress is a property of the viewer, not the quest, so a
              signed-out visitor gets no status badge — seven cards all
              reading "Not started" is noise, and it crowds the title. --%>
        <span :if={@logged_in} class={["badge text-nowrap", card_status_class(assigns)]}>
          {card_status_label(assigns)}
        </span>
        <%!-- The host's lock, next to the status it qualifies: "Ready to claim"
              on a quest with no Claim button reads as a broken page otherwise. --%>
        <span :if={@lock_label} class="badge badge-warning badge-sm gap-0.5 text-nowrap">
          <.icon name="hero-lock-closed-solid" class="w-3 h-3" />
          {@lock_label}
        </span>
        <span :if={@quest.category} class="badge badge-ghost badge-sm text-nowrap">
          {@quest.category}
        </span>
        <span
          :if={@quest.reset != "never" and not same_as_category?(@quest)}
          class="badge badge-ghost badge-sm text-nowrap"
        >
          {reset_label(@quest)}
        </span>
        <span
          :if={@chain_position && not @grouped?}
          class="badge badge-ghost badge-sm gap-0.5 text-nowrap"
          title={gettext("View quest chain")}
        >
          <.icon name="hero-link" class="w-3 h-3" />
          {elem(@chain_position, 0)}/{elem(@chain_position, 1)}
        </span>
        <span
          :if={@grouped?}
          class="badge badge-ghost badge-sm gap-0.5 text-nowrap"
          title={gettext("View every quest in this group")}
        >
          <.icon name="hero-rectangle-stack" class="w-3 h-3" />
          {@group_size}
        </span>
      </:badges>

      <%!-- Rewards --%>
      <%= if @quest.rewards != [] && not @secret? do %>
        <div class="flex flex-wrap gap-1">
          <span :for={reward <- @quest.rewards} class="badge badge-sm badge-ghost gap-1">
            <.icon
              name={
                if reward.type == "currency",
                  do: "hero-currency-dollar",
                  else: "hero-cube"
              }
              class="w-3 h-3"
            />
            {reward.amount} {reward.code}
          </span>
        </div>
      <% end %>

      <%!-- Countdown --%>
      <%= if @left do %>
        <div class="flex items-center gap-1.5 text-base-content/70">
          <.icon name="hero-clock" class="w-3.5 h-3.5" />
          <span class="text-xs">
            <%= if @quest.ends_at do %>
              {gettext("Ends in %{time}", time: format_duration(@left))}
            <% else %>
              {gettext("Resets in %{time}", time: format_duration(@left))}
            <% end %>
          </span>
        </div>
      <% end %>

      <%!-- Progress / claim (logged-in users only) --%>
      <%= if @logged_in do %>
        <div class="mt-3">
          <%= cond do %>
            <%!-- Locked outranks claimable: `before_quest_claim` would refuse
                  this, and a button that always errors is worse than a reason.
                  Progress still counts, so buying in mid-day finds it done. --%>
            <% @lock_label -> %>
              <div class="flex items-center gap-1.5 text-warning">
                <.icon name="hero-lock-closed-solid" class="w-4 h-4" />
                <span class="text-xs font-medium">{@lock_label}</span>
              </div>
            <% @claimable -> %>
              <button
                phx-click="claim"
                phx-value-key={@quest.key}
                class="btn btn-success btn-sm w-full"
              >
                <.icon name="hero-gift" class="w-4 h-4" />
                {gettext("Claim")}
              </button>
            <% @claimed? -> %>
              <div class="flex items-center gap-1.5 text-success">
                <.icon name="hero-check-circle-solid" class="w-4 h-4" />
                <span class="text-xs font-medium">
                  {gettext("Claimed")}
                  <span :if={@progress.completed_at} class="text-base-content/70 ms-1">
                    <.timestamp at={@progress.completed_at} format="date" />
                  </span>
                </span>
              </div>
            <% @done? -> %>
              <div class="flex items-center gap-1.5 text-success">
                <.icon name="hero-check-circle-solid" class="w-4 h-4" />
                <span class="text-xs font-medium">{gettext("Completed")}</span>
              </div>
            <% true -> %>
              <div :for={row <- @objective_rows} class="mb-1.5 last:mb-0">
                <div class="flex items-center justify-between mb-1">
                  <span class="text-xs text-base-content/70">{gettext("Status")}</span>
                  <span class="text-xs font-medium text-base-content/70">
                    {row.count} / {row.target}
                  </span>
                </div>
                <div class="w-full bg-base-300 rounded-full h-2 overflow-hidden">
                  <div
                    class={[
                      "h-2 rounded-full transition-all duration-500",
                      if(row.count > 0, do: "bg-primary", else: "bg-base-300")
                    ]}
                    style={"width: #{trunc(row.count / max(row.target, 1) * 100)}%"}
                  >
                  </div>
                </div>
              </div>
          <% end %>
        </div>
      <% end %>
    </.entity_card>
    """
  end
end
