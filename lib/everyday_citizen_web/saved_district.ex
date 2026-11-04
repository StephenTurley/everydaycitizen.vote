defmodule EverydayCitizenWeb.SavedDistrict do
  @moduledoc """
  Keeps a saved district (in the session, and on a signed-in account) from
  outliving its district map. District lines are redrawn from time to time, and
  a district key from an older map may name a different place, so a saved one
  from an older map is dropped and the visitor is asked to look up their address
  again. One saved before maps were recorded is taken to be on the map in use
  then (`config :everyday_citizen, :legacy_district_map`).
  Runs after `fetch_current_scope_for_user`, which restores an account's
  district into the session.
  """
  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3]

  alias EverydayCitizen.{Accounts, Reps}

  @notice "District lines have changed since you last looked up your address. Enter it again to see your representatives."

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case {get_session(conn, :district), get_session(conn, :district_map)} do
      {nil, _} ->
        conn

      {_district, nil} ->
        if legacy_map() == Reps.district_map(), do: stamp(conn), else: expire(conn)

      {_district, map} ->
        if map == Reps.district_map(), do: conn, else: expire(conn)
    end
  end

  defp stamp(conn) do
    map = Reps.district_map()

    with %Accounts.User{district: district, district_map: nil} = user when is_binary(district) <-
           user(conn),
         do: {:ok, _user} = Accounts.put_district(user, district, map)

    put_session(conn, :district_map, map)
  end

  defp expire(conn) do
    current = Reps.district_map()

    case user(conn) do
      %Accounts.User{district: district, district_map: ^current} when is_binary(district) ->
        conn |> put_session(:district, district) |> put_session(:district_map, current)

      user ->
        if user && user.district, do: {:ok, _user} = Accounts.put_district(user, nil, nil)

        conn
        |> delete_session(:district)
        |> delete_session(:district_map)
        |> put_flash(:info, @notice)
    end
  end

  defp legacy_map, do: Application.fetch_env!(:everyday_citizen, :legacy_district_map)

  defp user(conn) do
    case conn.assigns[:current_scope] do
      %{user: %Accounts.User{} = user} -> user
      _ -> nil
    end
  end
end
