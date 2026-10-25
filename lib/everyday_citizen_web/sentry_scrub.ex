defmodule EverydayCitizenWeb.SentryScrub do
  @moduledoc """
  What a request error report may carry. Bodies and cookies are never sent, and
  URLs, the referer included, lose their query string: a visitor's address (for finding their
  representatives) must never leave the app.

  Wired into `Sentry.PlugContext` in the endpoint.
  """

  @doc "Scrubber that sends nothing (request bodies and cookies)."
  @spec nothing(Plug.Conn.t()) :: map()
  def nothing(_conn), do: %{}

  @doc """
  Request headers as Sentry scrubs them by default, with the query string
  dropped from the referer: a search results page's URL holds what was typed.
  """
  @spec headers(Plug.Conn.t()) :: map()
  def headers(%Plug.Conn{} = conn) do
    case Sentry.PlugContext.default_header_scrubber(conn) do
      %{"referer" => referer} = headers -> %{headers | "referer" => without_query(referer)}
      headers -> headers
    end
  end

  defp without_query(url), do: url |> URI.parse() |> Map.put(:query, nil) |> URI.to_string()

  @doc "The request URL without its query string."
  @spec url(Plug.Conn.t()) :: String.t()
  def url(%Plug.Conn{} = conn) do
    conn |> Plug.Conn.request_url() |> without_query()
  end
end
