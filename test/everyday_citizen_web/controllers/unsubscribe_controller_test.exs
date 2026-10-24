defmodule EverydayCitizenWeb.UnsubscribeControllerTest do
  use EverydayCitizenWeb.ConnCase, async: true

  import EverydayCitizen.AccountsFixtures

  alias EverydayCitizen.{Digest, Repo}

  setup do
    user = user_fixture()
    %{user: user, token: Digest.unsubscribe_token(user)}
  end

  test "the link asks before turning the email off", %{conn: conn, user: user, token: token} do
    html = conn |> get(~p"/unsubscribe/#{token}") |> html_response(200)
    assert html =~ "Stop the daily email?"
    assert html =~ ~s(action="/unsubscribe/#{token}")
    assert Repo.reload!(user).digest_enabled
  end

  test "confirming turns it off, without signing in", %{conn: conn, user: user, token: token} do
    html = conn |> post(~p"/unsubscribe/#{token}") |> html_response(200)
    assert html =~ "won't get the daily email"
    refute Repo.reload!(user).digest_enabled
  end

  test "a mail program's one-click unsubscribe works", %{conn: conn, user: user, token: token} do
    conn
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> post(~p"/unsubscribe/#{token}", "List-Unsubscribe=One-Click")
    |> response(200)

    refute Repo.reload!(user).digest_enabled
  end

  test "a tampered link changes nothing", %{conn: conn, user: user, token: token} do
    html = conn |> post("/unsubscribe/#{token}x") |> html_response(404)
    assert html =~ "This link doesn't work"
    assert Repo.reload!(user).digest_enabled
  end
end
