defmodule GamendWeb.SwaggerController do
  use GamendWeb, :controller

  def index(conn, _params) do
    conn
    |> assign(:page_title, "API Documentation")
    |> render(:index)
  end
end
