defmodule EverydayCitizenWeb.RemoteIp do
  @moduledoc """
  The visitor's address for per-visitor limits, from a connected LiveView:
  Fly's X-Forwarded-For (its first entry), else the socket peer. Needs the
  socket's `:x_headers` and `:peer_data` connect info (endpoint).
  """
  import Phoenix.LiveView, only: [connected?: 1, get_connect_info: 2]

  @spec from_socket(Phoenix.LiveView.Socket.t()) :: String.t()
  def from_socket(socket) do
    if connected?(socket), do: lookup(socket), else: "unknown"
  end

  defp lookup(socket) do
    forwarded =
      for {"x-forwarded-for", value} <- get_connect_info(socket, :x_headers) || [],
          do: value |> String.split(",") |> hd() |> String.trim()

    case {forwarded, get_connect_info(socket, :peer_data)} do
      {[ip | _], _} -> ip
      {[], %{address: address}} -> address |> :inet.ntoa() |> to_string()
      _ -> "unknown"
    end
  end
end
