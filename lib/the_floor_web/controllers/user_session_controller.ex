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

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
