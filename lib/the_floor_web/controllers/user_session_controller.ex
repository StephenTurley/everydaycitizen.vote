defmodule TheFloorWeb.UserSessionController do
  use TheFloorWeb, :controller

  alias TheFloor.Accounts
  alias TheFloorWeb.UserAuth

  # Passkey sign-in: the login LiveView verified the passkey and handed over a
  # single-use token, because a LiveView cannot set the session cookie itself.
  def create(conn, %{"passkey" => %{"token" => token}}) do
    case Accounts.login_user_by_passkey_token(token) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Welcome back!")
        |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

      {:error, :invalid} ->
        conn
        |> put_flash(:error, "That sign-in expired. Please try again.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, "User confirmed successfully.")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  # magic link login
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      _ ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  @doc """
  Remembers a page on this site to return to after signing in (from "Follow"
  while signed out), then goes to the sign-in page. Only local paths are
  kept, so the link cannot send anyone to another site.
  """
  def sign_in_to(conn, params) do
    case local_path(params["to"]) do
      nil -> redirect(conn, to: ~p"/users/log-in")
      to -> conn |> put_session(:user_return_to, to) |> redirect(to: ~p"/users/log-in")
    end
  end

  defp local_path("/" <> rest = path) do
    if String.starts_with?(rest, ["/", "\\"]), do: nil, else: path
  end

  defp local_path(_), do: nil

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
