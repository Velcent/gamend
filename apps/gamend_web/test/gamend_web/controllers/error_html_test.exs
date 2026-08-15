defmodule GamendWeb.ErrorHTMLTest do
  @moduledoc """
  Phoenix's default renders the status message as plain text: a 404 was nine
  bytes reading "Not Found", which reads as "the whole site is down" and offers
  no way onward.

  The one hard rule for this module is that it must not fail. It runs when
  something has already gone wrong, sometimes without a conn, so every path
  here is exercised — including the ones with nothing to work from.
  """
  use ExUnit.Case, async: true

  import Phoenix.Template, only: [render_to_string: 4]

  defp render(template, assigns \\ %{}) do
    render_to_string(GamendWeb.ErrorHTML, template, "html", assigns)
  end

  describe "404" do
    test "is a real page, not a plain-text status" do
      html = render("404.html")

      assert html =~ "<!DOCTYPE html>"
      assert html =~ "404"
      refute html == "Not Found"
    end

    test "tells the reader the rest of the site works, and offers a way onward" do
      html = render("404.html")

      assert html =~ "rest of the site is fine"
      assert html =~ ~s(href="/")
    end

    test "wears the site's own theme rather than its own palette" do
      html = render("404.html")

      assert html =~ ~s(href="/assets/css/app.css")
      assert html =~ ~s(data-theme=)
      assert html =~ "bg-base-100"
    end

    test "is never indexed" do
      # It is a real URL returning real HTML; a crawler that ignores the status
      # code would otherwise file it as a thin page.
      assert render("404.html") =~ ~s(<meta name="robots" content="noindex, nofollow")
    end
  end

  describe "other statuses" do
    test "500 gets its own copy" do
      html = render("500.html")

      assert html =~ "500"
      assert html =~ "our side"
    end

    test "a status with no specific copy still renders a page" do
      html = render("418.html")

      assert html =~ "<!DOCTYPE html>"
      assert html =~ "418"
    end

    test "an unparsable template does not raise" do
      html = render("oops.html")

      assert html =~ "<!DOCTYPE html>"
      assert html =~ "500"
    end
  end

  describe "host-supplied links" do
    # The links go in as an assign rather than through `Application.put_env`:
    # this module is async, and a global put_env here would show up on every
    # error page another concurrent test happens to render.

    test "core links nowhere but Home by default" do
      # "/vocabulary" means nothing to a Gamend server that is not this one, so
      # core must not invent routes on a host's behalf.
      html = render("404.html", %{error_page_links: []})

      assert html =~ ~s(href="/")
      refute html =~ "vocabulary"
    end

    test "a host's own pages are rendered" do
      html = render("404.html", %{error_page_links: [%{label: "Vocabulary", path: "vocabulary"}]})

      assert html =~ ~s(href="/vocabulary")
    end

    test "they keep the reader's locale prefix" do
      html =
        render("404.html", %{
          conn: %Plug.Conn{assigns: %{locale: "ro"}},
          error_page_links: [%{label: "Vocabulary", path: "vocabulary"}]
        })

      assert html =~ ~s(href="/ro/vocabulary")
    end

    test "a malformed entry is skipped rather than crashing the error page" do
      html =
        render("404.html", %{
          error_page_links: [
            %{label: "", path: "empty"},
            "not a map",
            %{label: "Play", path: "/play"}
          ]
        })

      assert html =~ ~s(href="/play")
      refute html =~ "empty"
    end
  end

  describe "locale" do
    test "keeps the reader in their language" do
      conn = %Plug.Conn{assigns: %{locale: "ro"}}
      html = render("404.html", %{conn: conn})

      assert html =~ ~s(lang="ro")
      assert html =~ ~s(href="/ro/")
    end

    test "the default locale is not prefixed" do
      conn = %Plug.Conn{assigns: %{locale: "en"}}
      html = render("404.html", %{conn: conn})

      refute html =~ ~s(href="/en/)
    end

    test "renders with no conn at all" do
      # Errors raised before the pipeline sets anything still have to produce a
      # page rather than a second error.
      html = render("404.html")

      assert html =~ "<!DOCTYPE html>"
      assert html =~ ~s(lang=")
    end

    test "renders when the conn carries no locale" do
      html = render("404.html", %{conn: %Plug.Conn{assigns: %{}}})

      assert html =~ "<!DOCTYPE html>"
    end

    test "a right-to-left locale sets dir" do
      conn = %Plug.Conn{assigns: %{locale: "ar"}}

      assert render("404.html", %{conn: conn}) =~ ~s(dir="rtl")
    end
  end
end
