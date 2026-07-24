defmodule GameServerWeb.QuestsLive do
  @moduledoc """
  Public-facing quests page.

  Anonymous users browse the catalog (hidden quests appear as teasers).
  Logged-in users see their progress per reset period, can filter by kind
  and status, and claim completed quests.
  """
  use GameServerWeb, :live_view

  alias GameServer.Accounts.Scope
  alias GameServer.Quests
  alias GameServer.Quests.Quest
  alias GameServerWeb.Plugs.FeatureGate

  @page_size 50

  @kind_filters [nil | Quest.kinds()]
  @status_filters [nil, "in_progress", "claimable", "done"]

  @impl true
  def mount(_params, _session, socket) do
    unless FeatureGate.enabled?("LIST_QUESTS_ENABLED", true) do
      raise GameServerWeb.NotFoundError
    end

    user = get_user(socket)

    if connected?(socket) do
      Quests.subscribe_quests()
      if user, do: Phoenix.PubSub.subscribe(GameServer.PubSub, "user:#{user.id}")
    end

    socket =
      socket
      |> assign(:locale, Gettext.get_locale(GameServerWeb.Gettext))
      |> assign(:page_title, gettext("Quests"))
      |> assign(:page, 1)
      |> assign(:page_size, @page_size)
      |> assign(:kind, nil)
      |> assign(:status, nil)
      |> load_quests()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("kind", %{"kind" => kind}, socket) do
    kind = if kind == "", do: nil, else: kind

    {:noreply,
     socket
     |> assign(:kind, if(kind in @kind_filters, do: kind))
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
    kind = socket.assigns.kind
    status = socket.assigns.status

    {entries, total_count, claimable} =
      if user do
        opts = [page: page, page_size: page_size, kind: kind, status: status]

        {Quests.list_user_quests(user.id, opts),
         Quests.count_user_quests(user.id, kind: kind, status: status),
         Quests.claimable_count(user.id)}
      else
        {catalog_entries, total} = anonymous_catalog(kind, page, page_size)
        {catalog_entries, total, 0}
      end

    socket
    |> assign(:entries, entries)
    |> assign(:total_count, total_count)
    |> assign(:total_pages, max(ceil(total_count / page_size), 1))
    |> assign(:claimable_count, claimable)
    |> assign(:chain_positions, chain_positions(Quests.active_quests()))
    |> assign(:now, DateTime.utc_now(:second))
  end

  # Position of each chained quest within its prerequisite line, as
  # {position, total} — e.g. tier 3 of 7. Quests without prerequisite links
  # get no entry. Cycles (malformed data) are cut off by the depth cap.
  @max_chain_walk 20

  defp chain_positions(quests) do
    prereq_by_key = Map.new(quests, &{&1.key, &1.prerequisite_quest_key})

    depths =
      Map.new(prereq_by_key, fn {key, _} -> {key, chain_depth(key, prereq_by_key, 0)} end)

    totals =
      Enum.reduce(depths, %{}, fn {key, depth}, acc ->
        root = chain_root(key, prereq_by_key, 0)
        Map.update(acc, root, depth + 1, &max(&1, depth + 1))
      end)

    depths
    |> Enum.map(fn {key, depth} ->
      {key, {depth + 1, Map.get(totals, chain_root(key, prereq_by_key, 0), depth + 1)}}
    end)
    |> Enum.filter(fn {_key, {_pos, total}} -> total > 1 end)
    |> Map.new()
  end

  defp chain_depth(key, prereq_by_key, hops) when hops < @max_chain_walk do
    case Map.get(prereq_by_key, key) do
      nil -> 0
      prereq -> 1 + chain_depth(prereq, prereq_by_key, hops + 1)
    end
  end

  defp chain_depth(_key, _prereq_by_key, _hops), do: 0

  defp chain_root(key, prereq_by_key, hops) when hops < @max_chain_walk do
    case Map.get(prereq_by_key, key) do
      nil -> key
      prereq -> chain_root(prereq, prereq_by_key, hops + 1)
    end
  end

  defp chain_root(key, _prereq_by_key, _hops), do: key

  defp anonymous_catalog(kind, page, page_size) do
    now = DateTime.utc_now(:second)

    visible =
      Quests.active_quests()
      |> Enum.filter(fn q ->
        kind in [nil, q.kind] and within_window?(q, now)
      end)

    entries =
      visible
      |> Enum.drop((page - 1) * page_size)
      |> Enum.take(page_size)
      |> Enum.map(fn quest -> %{quest: quest, progress: nil, claimable: false} end)

    {entries, length(visible)}
  end

  defp within_window?(quest, now) do
    (is_nil(quest.starts_at) or DateTime.compare(quest.starts_at, now) != :gt) and
      (is_nil(quest.ends_at) or DateTime.compare(quest.ends_at, now) == :gt)
  end

  defp kind_label(nil), do: gettext("All")
  defp kind_label("achievement"), do: gettext("Achievements")
  defp kind_label("daily"), do: gettext("Daily")
  defp kind_label("weekly"), do: gettext("Weekly")
  defp kind_label("event"), do: gettext("Events")
  defp kind_label("chain"), do: gettext("Chains")

  defp status_label(nil), do: gettext("All")
  defp status_label("in_progress"), do: gettext("In Progress")
  defp status_label("claimable"), do: gettext("Claimable")
  defp status_label("done"), do: gettext("Completed")

  # Time left in the quest's current cycle: end of UTC day/ISO week for
  # daily/weekly, ends_at for event quests, nothing for permanent kinds.
  defp time_left(%Quest{kind: "daily"}, now) do
    tomorrow = now |> DateTime.to_date() |> Date.add(1)
    DateTime.diff(DateTime.new!(tomorrow, ~T[00:00:00]), now)
  end

  defp time_left(%Quest{kind: "weekly"}, now) do
    date = DateTime.to_date(now)
    next_monday = Date.add(date, 8 - Date.day_of_week(date))
    DateTime.diff(DateTime.new!(next_monday, ~T[00:00:00]), now)
  end

  defp time_left(%Quest{kind: "event", ends_at: %DateTime{} = ends_at}, now) do
    max(DateTime.diff(ends_at, now), 0)
  end

  defp time_left(_quest, _now), do: nil

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
            <h1 class="text-3xl font-bold">
              {gettext("Quests")}
              <span class="text-base-content/50 font-normal">({@total_count})</span>
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
            :for={kind <- [nil, "daily", "weekly", "event", "achievement", "chain"]}
            role="tab"
            phx-click="kind"
            phx-value-kind={kind || ""}
            class={["tab", @kind == kind && "tab-active"]}
          >
            {kind_label(kind)}
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
          <div class="text-center py-16 text-base-content/50">
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
      </div>
    </Layouts.app>
    """
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

    assigns =
      assigns
      |> assign(:quest, quest)
      |> assign(:progress, progress)
      |> assign(:claimable, claimable)
      |> assign(:done?, done?)
      |> assign(:claimed?, claimed?)
      |> assign(:left, left)
      |> assign(:secret?, secret?)
      |> assign(:objective_rows, if(secret?, do: [], else: objective_rows(quest, progress)))
      |> assign(
        :localized_title,
        if(secret?, do: "???", else: Quest.localized_title(quest, assigns.locale))
      )
      |> assign(
        :localized_desc,
        if(secret?,
          do: gettext("Hidden"),
          else: Quest.localized_description(quest, assigns.locale)
        )
      )

    ~H"""
    <div class={[
      "card bg-base-100 shadow-sm hover:shadow-md transition-all duration-200 border",
      cond do
        @claimable -> "border-success"
        @done? -> "border-success/30"
        true -> "border-base-300"
      end
    ]}>
      <div class="card-body p-4">
        <div class="flex items-start gap-3">
          <div class={[
            "flex-shrink-0 w-12 h-12 rounded-lg flex items-center justify-center text-2xl",
            if(@done?, do: "bg-success/20 text-success", else: "bg-base-300 text-base-content/40")
          ]}>
            <%= if @quest.icon_url && @quest.icon_url != "" and not @secret? do %>
              <img
                src={@quest.icon_url}
                alt={@quest.title}
                loading="lazy"
                decoding="async"
                class={["w-8 h-8 object-contain", if(!@done?, do: "opacity-60")]}
              />
            <% else %>
              <.icon
                name={
                  cond do
                    @secret? -> "hero-question-mark-circle"
                    @done? -> "hero-trophy"
                    true -> "hero-map"
                  end
                }
                class="w-7 h-7"
              />
            <% end %>
          </div>

          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2">
              <h3 class={[
                "font-semibold text-sm leading-tight truncate",
                if(!@done?, do: "text-base-content/80")
              ]}>
                {@localized_title}
              </h3>
              <span class="badge badge-xs badge-outline flex-shrink-0">
                {kind_label(@quest.kind)}
              </span>
              <span
                :if={@chain_position}
                class="badge badge-xs badge-ghost flex-shrink-0 gap-0.5"
                title={gettext("Quests")}
              >
                <.icon name="hero-link" class="w-3 h-3" />
                {elem(@chain_position, 0)}/{elem(@chain_position, 1)}
              </span>
            </div>

            <p class="text-xs mt-1 line-clamp-2 text-base-content/60">
              {@localized_desc}
            </p>

            <%!-- Rewards --%>
            <%= if @quest.rewards != [] and not @secret? do %>
              <div class="flex flex-wrap gap-1 mt-2">
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
          </div>
        </div>

        <%!-- Countdown --%>
        <%= if @left do %>
          <div class="flex items-center gap-1.5 mt-2 text-base-content/40">
            <.icon name="hero-clock" class="w-3.5 h-3.5" />
            <span class="text-xs">
              <%= if @quest.kind == "event" do %>
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
                    <span :if={@progress.completed_at} class="text-base-content/40 ml-1">
                      {Calendar.strftime(@progress.completed_at, "%b %d, %Y")}
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
                    <span class="text-xs text-base-content/50">{gettext("Status")}</span>
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
      </div>
    </div>
    """
  end
end
