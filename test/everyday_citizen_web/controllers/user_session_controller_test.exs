defmodule EverydayCitizenWeb.UserSessionControllerTest do
  use EverydayCitizenWeb.ConnCase, async: true

  import EverydayCitizen.AccountsFixtures
  alias EverydayCitizen.Accounts

  setup do
    %{unconfirmed_user: unconfirmed_user_fixture(), user: user_fixture()}
  end

  describe "the district across sign-in" do
    setup do
      EverydayCitizen.FloorFixtures.iowa!()
      :ok
    end

    defp sign_in(conn, user) do
      {token, _hashed_token} = generate_user_magic_link_token(user)
      post(conn, ~p"/users/log-in", %{"user" => %{"token" => token}})
    end

    test "a district looked up before signing in is saved on an account without one", %{
      conn: conn,
      user: user
    } do
      conn = conn |> init_test_session(%{district: "IA-1"}) |> sign_in(user)

      assert get_session(conn, :district) == "IA-1"
      assert Accounts.get_user!(user.id).district == "IA-1"
    end

    test "an account's district is used when the session has none", %{conn: conn, user: user} do
      {:ok, user} = Accounts.put_district(user, "IA-1")
      conn = sign_in(conn, user)
      assert get_session(conn, :district) == "IA-1"
    end

    test "a new district found while signed out replaces the account's at sign-in", %{
      conn: conn,
      user: user
    } do
      {:ok, user} = Accounts.put_district(user, "IA-1")
      conn = conn |> init_test_session(%{district: "IA-2"}) |> sign_in(user)

      assert get_session(conn, :district) == "IA-2"
      assert Accounts.get_user!(user.id).district == "IA-2"
    end

    test "after a browser restart, the remembered sign-in brings the district back", %{
      conn: conn,
      user: user
    } do
      {:ok, user} = Accounts.put_district(user, "IA-1")
      {token, _hashed_token} = generate_user_magic_link_token(user)

      signed_in =
        post(conn, ~p"/users/log-in", %{"user" => %{"token" => token, "remember_me" => "true"}})

      remember = signed_in.resp_cookies["_everyday_citizen_web_user_remember_me"]

      conn =
        build_conn()
        |> put_req_cookie("_everyday_citizen_web_user_remember_me", remember.value)
        |> get(~p"/this-week")

      assert get_session(conn, :district) == "IA-1"
    end

    test "signed in, finding a new district replaces the account's", %{conn: conn, user: user} do
      {:ok, user} = Accounts.put_district(user, "IA-1")
      conn = conn |> sign_in(user) |> recycle() |> get(~p"/district/IA-2")

      assert get_session(conn, :district) == "IA-2"
      assert Accounts.get_user!(user.id).district == "IA-2"
    end
  end

  describe "POST /users/log-in - magic link" do
    test "logs the user in", %{conn: conn, user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the header
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ ~p"/users/settings"
      refute response =~ ">\n            Sign in"
      _ = user
    end

    test "confirms unconfirmed user", %{conn: conn, unconfirmed_user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)
      refute user.confirmed_at

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token},
          "_action" => "confirmed"
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "User confirmed successfully."

      assert Accounts.get_user!(user.id).confirmed_at

      # Now do a logged in request and assert on the header
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ ~p"/users/settings"
      refute response =~ ">\n            Sign in"
      _ = user
    end

    test "redirects to login page when magic link is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => "invalid"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "The link is invalid or it has expired."

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end

  describe "GET /users/sign-in-to" do
    test "remembers where to return after signing in", %{conn: conn, user: user} do
      conn = get(conn, ~p"/users/sign-in-to?to=/bills/119-s-5")
      assert redirected_to(conn) == ~p"/users/log-in"

      {token, _} = generate_user_magic_link_token(user)
      conn = conn |> recycle() |> post(~p"/users/log-in", %{"user" => %{"token" => token}})
      assert redirected_to(conn) == "/bills/119-s-5"
    end

    test "never returns to another site", %{conn: conn} do
      for to <- [
            "https://evil.example/",
            "//evil.example/x",
            "javascript:alert(1)",
            "/a\\b",
            "/x\nSet-Cookie: a=b",
            "/\t/evil.example"
          ] do
        conn = get(conn, ~p"/users/sign-in-to?#{[to: to]}")
        assert redirected_to(conn) == ~p"/users/log-in"
        refute get_session(conn, :user_return_to)
      end
    end
  end
end
