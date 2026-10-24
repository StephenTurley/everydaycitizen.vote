defmodule TheFloorWeb.DistrictController do
  @moduledoc """
  Remembers a visitor's district (never their address) in the session, then
  shows its reps. `show` is reached from the home page after a live lookup;
  `create` is the same lookup for a form posted before the live connection is
  up, so the address is never sent in a URL.
  """
  use TheFloorWeb, :controller

  alias TheFloor.Reps
  alias TheFloorWeb.HomeLive

  def show(conn, %{"district" => district}) do
    if Reps.known_district?(district) do
      conn |> put_session(:district, district) |> redirect(to: ~p"/reps/#{district}")
    else
      redirect(conn, to: ~p"/")
    end
  end

  def create(conn, %{"address" => address}) do
    with {:ok, address} <- HomeLive.present(address),
         {:ok, district, _reps} <- Reps.find(address) do
      conn |> put_session(:district, district) |> redirect(to: ~p"/reps/#{district}")
    else
      {:error, reason} ->
        conn |> put_flash(:error, HomeLive.message(reason)) |> redirect(to: ~p"/")
    end
  end
end
