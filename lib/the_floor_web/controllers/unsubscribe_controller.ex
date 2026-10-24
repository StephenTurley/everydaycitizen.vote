defmodule TheFloorWeb.UnsubscribeController do
  @moduledoc """
  The daily email's unsubscribe link. `GET` asks first (link scanners open
  links); `POST` turns the email off, including a mail program's RFC 8058
  one-click request. The signed token is the only credential, so no sign-in
  and no CSRF token are needed, and an old link can only turn email off.
  """
  use TheFloorWeb, :controller

  alias TheFloor.{Accounts, Digest}

  def show(conn, %{"token" => token}) do
    case user(token) do
      nil -> not_found(conn)
      _user -> render(conn, :confirm, token: token)
    end
  end

  def delete(conn, %{"token" => token}) do
    case user(token) do
      nil ->
        not_found(conn)

      user ->
        {:ok, _} = Accounts.set_digest(user, false)
        render(conn, :done)
    end
  end

  defp user(token) do
    case Digest.verify_unsubscribe(token) do
      {:ok, id} -> Accounts.get_user(id)
      :error -> nil
    end
  end

  defp not_found(conn), do: conn |> put_status(:not_found) |> render(:invalid)
end
