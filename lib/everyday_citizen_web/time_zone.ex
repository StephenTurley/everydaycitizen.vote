defmodule EverydayCitizenWeb.TimeZone do
  @moduledoc """
  The reader's time zone, used for "today" and for clock times. The browser
  reports it when the page connects (`time_zone` in the LiveSocket params) and
  keeps it in the `tz` cookie, which this plug copies into the session so the
  first render of later visits uses it too. Without either (a first visit, a
  crawler) it is the legislature's own zone. Only names in the time-zone
  database are taken.

  As a plug (browser pipeline) it copies the cookie; as an `on_mount` hook
  (every LiveView) it assigns `:time_zone` and `:zone_label` (e.g. "PDT").
  """
  import Plug.Conn

  alias EverydayCitizen.{Clock, Legislature, Reps}

  @cookie "tz"

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)
    zone = conn.cookies[@cookie]

    cond do
      not Clock.zone?(zone) -> conn
      get_session(conn, "time_zone") == zone -> conn
      true -> put_session(conn, "time_zone", zone)
    end
  end

  def on_mount(:default, _params, session, socket) do
    zone =
      [connect_zone(socket), session["time_zone"]]
      |> Enum.find(&Clock.zone?/1)
      |> Kernel.||(Legislature.time_zone(Reps.jurisdiction()))

    {:cont, Phoenix.Component.assign(socket, time_zone: zone, zone_label: label(zone))}
  end

  defp connect_zone(socket) do
    if Phoenix.LiveView.connected?(socket),
      do: (Phoenix.LiveView.get_connect_params(socket) || %{})["time_zone"]
  end

  defp label(zone), do: zone |> DateTime.now!() |> Calendar.strftime("%Z")
end
