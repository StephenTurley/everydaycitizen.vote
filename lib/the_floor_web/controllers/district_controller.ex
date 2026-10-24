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
      remember(conn, district)
    else
      redirect(conn, to: ~p"/")
    end
  end

  def create(conn, %{"zip" => zip, "street" => street}) do
    with {:ok, zip} <- HomeLive.valid_zip(String.trim(zip)),
         {:ok, street} <- HomeLive.present(street) do
      locate(conn, "#{street}, #{zip}")
    else
      {:error, reason} -> back_home(conn, reason)
    end
  end

  def create(conn, %{"zip" => zip}) do
    case HomeLive.valid_zip(String.trim(zip)) do
      {:ok, zip} -> by_zip(conn, Reps.districts_for_postal_code(zip))
      {:error, reason} -> back_home(conn, reason)
    end
  end

  def create(conn, %{"address" => address}) do
    case HomeLive.present(address) do
      {:ok, address} -> locate(conn, address)
      {:error, reason} -> back_home(conn, reason)
    end
  end

  defp by_zip(conn, [district]), do: remember(conn, district)
  defp by_zip(conn, [_ | _]), do: back_home(conn, :split_zip)
  defp by_zip(conn, []), do: back_home(conn, :unknown_zip)

  defp locate(conn, address) do
    case Reps.find(address) do
      {:ok, district, _reps} -> remember(conn, district)
      {:error, reason} -> back_home(conn, reason)
    end
  end

  defp remember(conn, district),
    do: conn |> put_session(:district, district) |> redirect(to: ~p"/reps/#{district}")

  defp back_home(conn, reason),
    do: conn |> put_flash(:error, HomeLive.message(reason)) |> redirect(to: ~p"/")
end
