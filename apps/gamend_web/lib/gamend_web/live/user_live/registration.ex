defmodule GamendWeb.UserLive.Registration do
  use GamendWeb, :live_view

  alias Gamend.Accounts
  alias Gamend.Accounts.{User, UserToken}
  alias Gamend.Repo

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="mx-auto max-w-sm lg:max-w-4xl space-y-4">
        <div class="text-center">
          <h1 class="text-4xl font-black text-base-content/95">{gettext("Register")}</h1>
          <p class="text-sm text-base-content/70 mt-2">
            <.link navigate={~p"/users/log_in"} class="font-semibold text-brand hover:underline">
              {gettext("Log in")}
            </.link>
          </p>
        </div>

        <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:email]}
            type="email"
            label={gettext("Email")}
            autocomplete="username"
            required
            phx-mounted={JS.focus()}
          />

          <.captcha id="registration_captcha" />

          <.button
            phx-disable-with={gettext("Loading...")}
            class="btn btn-primary w-full"
          >
            {gettext("Register")}
          </.button>
        </.form>

        <.oauth_buttons label={gettext("Register")} />
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user_id: user_id}}} = socket)
      when is_binary(user_id) do
    require Logger
    Logger.info("[Registration] User already logged in, redirecting to signed_in_path")
    {:ok, Phoenix.LiveView.redirect(socket, external: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_email(%User{}, %{}, validate_unique: false)

    client_ip = GamendWeb.LiveHelpers.client_ip(socket)

    {:ok,
     socket
     |> assign(:page_title, gettext("Register"))
     |> assign(:client_ip, client_ip)
     |> assign_form(changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params} = params, socket) do
    with :ok <- GamendWeb.LiveHelpers.check_rate_limit(socket.assigns.client_ip, :auth),
         :ok <- GamendWeb.LiveHelpers.check_captcha(socket, params) do
      do_save(user_params, socket)
    else
      {:error, %Phoenix.LiveView.Socket{} = socket} ->
        {:noreply, socket}

      {:error, _retry_after} ->
        {:noreply,
         put_flash(socket, :error, gettext("Too many attempts. Please try again later."))}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    # `validate_unique: false` on the keystroke path.
    #
    # The registration changeset defaults to `unsafe_validate_unique`, so every
    # keystroke ran a query and rendered "has already been taken" — an
    # unauthenticated, unthrottled oracle for "does this address have an account
    # here?", one email per keystroke. Only `save` is rate-limited and captcha'd.
    # Submitting still checks uniqueness, and the database's unique index is
    # what actually enforces it.
    changeset =
      %User{}
      |> Accounts.change_user_registration(user_params, validate_unique: false)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  defp do_save(user_params, socket) do
    notifier =
      Application.get_env(:gamend_web, :user_notifier, Gamend.Accounts.UserNotifier)

    case Accounts.register_user_and_deliver(
           user_params,
           fn t -> url(~p"/users/confirm/#{t}") end,
           notifier
         ) do
      {:ok, user} ->
        # Check if this is the first user (admin users are auto-created as first user)
        is_first_user = user.is_admin

        if is_first_user do
          # First user: auto-confirm and auto-login
          {:ok, user} = Accounts.confirm_user(user)

          # Generate a magic link token for auto-login
          {token, user_token} = UserToken.build_email_token(user, "login")
          Repo.insert!(user_token)

          # Redirect to login with the token (will auto-login the confirmed user)
          {:noreply,
           socket
           |> put_flash(
             :info,
             gettext("Success.")
           )
           |> push_navigate(to: ~p"/users/log_in/#{token}")}
        else
          # Not the first user: a confirmation email was sent inside the
          # registration transaction. Inform the user to check their inbox.
          {:noreply,
           socket
           |> put_flash(
             :info,
             gettext("Success.")
           )
           |> push_navigate(to: ~p"/users/log_in")}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}

      {:error, reason} ->
        # If email delivery failed the user creation was rolled back. Keep the
        # form open and present a friendly error message.
        require Logger
        Logger.error("register_user_and_deliver failed: #{inspect(reason)}")

        changeset = Accounts.change_user_registration(%User{}, user_params)

        {:noreply,
         socket
         |> put_flash(
           :error,
           gettext("Failed")
         )
         |> assign(check_errors: true)
         |> assign_form(Map.put(changeset, :action, :insert))}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
