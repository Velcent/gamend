defmodule GamendWeb.PageController do
  use GamendWeb, :controller

  alias GamendWeb.PresentationPage

  def home(conn, _params) do
    render_presentation_page(conn, "/", gettext("Home"))
  end

  def configured_page(conn, %{"path" => path}) do
    render_presentation_page(conn, "/" <> Enum.join(path, "/"), gettext("Page"))
  end

  def privacy(conn, _params) do
    conn
    |> assign(:page_title, gettext("Privacy"))
    |> render(:privacy)
  end

  def data_deletion(conn, _params) do
    conn
    |> assign(:page_title, gettext("Delete"))
    |> render(:data_deletion)
  end

  def terms(conn, _params) do
    conn
    |> assign(:page_title, gettext("Terms"))
    |> render(:terms)
  end

  defp render_presentation_page(conn, path, fallback_title) do
    locale = Gettext.get_locale(GamendWeb.Gettext)
    theme = GamendWeb.Layouts.resolve_theme(locale, conn.assigns[:theme] || %{})

    case PresentationPage.page_for_path(theme, path) || missing_home_page(theme, path) do
      nil ->
        # Not `text("Not Found")`: this decides for itself that the request is a
        # 404, so it never reaches `render_errors` and the reader got nine bytes
        # of plain text while the error template sat unused.
        GamendWeb.ErrorResponse.not_found(conn)

      page ->
        # Hero and section buttons are config hrefs like "/play"; without this
        # every call to action on /fr drops the reader back to a clean URL.
        page = GamendWeb.HostLayouts.localize_hrefs(page, locale)

        # Rendered here rather than in the template so the memo has a key: the
        # body is a pure function of the theme page and the locale, and the
        # template does not know either.
        background_icons = Map.get(theme, "background_icons") || []

        conn
        |> assign(:page_title, PresentationPage.page_title(page, fallback_title))
        |> render(:presentation_page,
          presentation_body: PresentationPage.cached_body(page, background_icons, locale, path),
          theme: theme
        )
    end
  end

  defp missing_home_page(theme, "/") do
    %{
      "path" => "/",
      "hero" => %{
        "title" => Map.get(theme, "title", ""),
        "text" => Map.get(theme, "description", ""),
        "image" => %{
          "light" => Map.get(theme, "banner", "/images/banner.png"),
          "alt" => Map.get(theme, "title", "")
        }
      },
      "sections" => []
    }
  end

  defp missing_home_page(_theme, _path), do: nil
end
