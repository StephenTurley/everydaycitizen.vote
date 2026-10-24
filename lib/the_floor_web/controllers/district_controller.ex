defmodule TheFloorWeb.DistrictController do
  @moduledoc """
  Remembers a visitor's district (never their address) in the session, then
  shows its reps. Reached from the home page after the address lookup.
  """
  use TheFloorWeb, :controller

  def show(conn, %{"district" => district}) do
    conn
    |> put_session(:district, district)
    |> redirect(to: ~p"/reps/#{district}")
  end
end
