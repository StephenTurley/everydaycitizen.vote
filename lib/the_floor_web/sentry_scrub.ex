defmodule TheFloorWeb.SentryScrub do
  @moduledoc """
  What a request error report may carry. Bodies and cookies are never sent, and
  URLs lose their query string: a visitor's address (for finding their
  representatives) must never leave the app.

  Wired into `Sentry.PlugContext` in the endpoint.
  """

  @doc "Scrubber that sends nothing (request bodies and cookies)."
  @spec nothing(Plug.Conn.t()) :: map()
  def nothing(_conn), do: %{}

  @doc "The request URL without its query string."
  @spec url(Plug.Conn.t()) :: String.t()
  def url(%Plug.Conn{} = conn) do
    conn |> Plug.Conn.request_url() |> URI.parse() |> Map.put(:query, nil) |> URI.to_string()
  end
end
