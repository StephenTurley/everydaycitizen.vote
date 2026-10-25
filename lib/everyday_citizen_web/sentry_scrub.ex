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
  extras and request. Everything else is sent as it came, and anything that
  is not an event (a transaction) passes through. A value that cannot be
  scrubbed is dropped rather than sent, and the event still goes.
  """
  @spec before_send(term()) :: term()
  def before_send(%Sentry.Event{} = event) do
    extra =
      event.extra
      |> Map.drop(@process_extras)
      |> Enum.flat_map(fn {key, value} ->
        case safely_strip(value) do
          {:ok, scrubbed} -> [{key, scrubbed}]
          :error -> []
        end
      end)
      |> Map.new()

    %{event | extra: extra, request: scrub_request(event.request)}
  end

  def before_send(other), do: other

  defp scrub_request(nil), do: nil

  defp scrub_request(request) do
    %{
      request
      | url: scrubbed_or_nil(request.url),
        query_string: nil,
        headers: scrubbed_or_nil(request.headers)
    }
  end

  defp scrubbed_or_nil(value) do
    case safely_strip(value) do
      {:ok, scrubbed} -> scrubbed
      :error -> nil
    end
  end

  defp safely_strip(value) do
    {:ok, strip_queries(value)}
  rescue
    _ -> :error
  end

  defp strip_queries(value) when is_binary(value), do: Regex.replace(@url_query, value, "\\1")
  # walks improper lists too: the tail of [a | b] may be a string
  defp strip_queries([head | tail]), do: [strip_queries(head) | strip_queries(tail)]

  defp strip_queries(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> strip_queries() |> List.to_tuple()

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
