defmodule TheFloorWeb.CanonicalHost do
  @moduledoc """
  Redirects (301) any other host, such as `www.` or the Fly app hostname, to the
  canonical host over https, keeping path and query. LiveView only accepts
  socket connections from the configured host, so pages must load there.

  The host comes from `:host` in the plug options, else from
  `config :the_floor, :canonical_host` at request time (set from `PHX_HOST` in
  production). With no host configured, every request passes through.
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    case Keyword.get_lazy(opts, :host, fn -> Application.get_env(:the_floor, :canonical_host) end) do
      host when is_binary(host) and host != conn.host -> redirect(conn, host)
      _ -> conn
    end
  end

  defp redirect(conn, host) do
    query = if conn.query_string == "", do: "", else: "?" <> conn.query_string

    conn
    |> put_resp_header("location", "https://#{host}#{conn.request_path}#{query}")
    |> send_resp(301, "")
    |> halt()
  end
end
