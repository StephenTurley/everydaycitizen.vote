defmodule EverydayCitizenWeb.SentryScrub do
  @moduledoc """
  What a request error report may carry. Bodies and cookies are never sent, and
  URLs, the referer included, lose their query string: a visitor's address (for finding their
  representatives) must never leave the app.

  Wired into `Sentry.PlugContext` in the endpoint, and `before_send/1` into the
  Sentry config for every report, crash reports included.
  """

  # a URL's query string, wherever it sits in a string: the URL keeps its path
  # and fragment
  @url_query ~r{([a-z][a-z0-9+.\-]*://[^\s?#"'<>]*)\?[^\s#"'<>]*}iu

  # what Sentry's logger handler copies from a crashing process: for a LiveView,
  # its assigns (what was searched) and its join payload (a URL with the query)
  @process_extras [:genserver_state, :last_message, "genserver_state", "last_message"]

  @doc """
  Sentry's `before_send` callback: drops a crashed process's state and last
  message from the event's extras, and the query string from every URL in its
  extras and request. Everything else is sent as it came.
  """
  @spec before_send(Sentry.Event.t()) :: Sentry.Event.t()
  def before_send(%Sentry.Event{} = event) do
    %{
      event
      | extra: event.extra |> Map.drop(@process_extras) |> strip_queries(),
        request: scrub_request(event.request)
    }
  end

  defp scrub_request(nil), do: nil

  defp scrub_request(request) do
    %{
      request
      | url: strip_queries(request.url),
        query_string: nil,
        headers: strip_queries(request.headers)
    }
  end

  defp strip_queries(value) when is_binary(value), do: Regex.replace(@url_query, value, "\\1")
  defp strip_queries(value) when is_list(value), do: Enum.map(value, &strip_queries/1)

  defp strip_queries(value) when is_map(value) and not is_struct(value),
    do: Map.new(value, fn {k, v} -> {k, strip_queries(v)} end)

  defp strip_queries(value), do: value

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
