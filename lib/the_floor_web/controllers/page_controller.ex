defmodule TheFloorWeb.PageController do
  use TheFloorWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
