defmodule EverydayCitizenWeb.SearchController do
  @moduledoc """
  Where the header's search box posts. It decides where a query goes before
  any URL holds it: nothing typed goes back to the page it came from, an
  address or ZIP code (or a state and ZIP that no bill's number matches, see
  `Search.address_like?/1`) goes to the find-your-reps lookup on the home page
  (without the query), a bill's own number goes straight to that bill, and
  anything else opens the results page.
  """
  use EverydayCitizenWeb, :controller

  alias EverydayCitizen.Search
  alias EverydayCitizen.Search.Query

  @address_message "That looks like an address. Enter it here to find your representatives."

  @doc "The message shown when a query looks like an address."
  def address_message, do: @address_message

  def create(conn, params) do
    case Query.classify(if is_binary(params["q"]), do: params["q"]) do
      :empty ->
        redirect(conn, to: back(conn))

      :address ->
        to_address_lookup(conn)

      {:search, query} ->
        if Search.address_like?(query), do: to_address_lookup(conn), else: to_search(conn, query)
    end
  end

  defp to_search(conn, query) do
    case Search.bill_by_number(query) do
      {:one, bill} -> redirect(conn, to: ~p"/bills/#{bill.external_id}")
      _ -> redirect(conn, to: ~p"/search?#{[q: query.text]}")
    end
  end

  defp to_address_lookup(conn),
    do: conn |> put_flash(:info, @address_message) |> redirect(to: ~p"/")

  # the referring page on this site, or the home page
  defp back(conn) do
    with [referer] <- get_req_header(conn, "referer"),
         %URI{host: host, path: "/" <> _ = path, query: query} <- URI.parse(referer),
         true <- host == conn.host and not String.starts_with?(path, "//") do
      if query, do: "#{path}?#{query}", else: path
    else
      _ -> ~p"/"
    end
  end
end
