defmodule TheFloorWeb.UserLive.SettingsTest do
  use TheFloorWeb.ConnCase, async: true

  alias TheFloor.Accounts
  import Phoenix.LiveViewTest
  import TheFloor.AccountsFixtures
  import TheFloor.WebAuthnFixtures

  describe "Settings page" do
    test "renders settings page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      assert html =~ "Your account"
      assert html =~ "Change email"
      refute html =~ "assword"
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "without a recent sign-in, the page opens but changing the email asks to confirm", %{
      conn: conn
    } do
      {:ok, view, html} =
        conn
        |> log_in_user(user_fixture(),
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
        )
        |> live(~p"/users/settings")

      assert html =~ "Your account"
      refute has_element?(view, "#email_form")
      assert has_element?(view, ~s(a[href="/users/log-in"]), "confirm it")
    end
  end

  describe "update email form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user email", %{conn: conn, user: user} do
      new_email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => new_email}
        })
        |> render_submit()

      assert result =~ "We sent a link to the new address"
      assert Accounts.get_user_by_email(user.email)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#email_form")
        |> render_change(%{
          "action" => "update_email",
          "user" => %{"email" => "with spaces"}
        })

      assert result =~ "Change email"
      assert result =~ "must have the @ sign and no spaces"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => user.email}
        })
        |> render_submit()

      assert result =~ "Change email"
      assert result =~ "did not change"
    end
  end

  describe "confirm email" do
    setup %{conn: conn} do
      user = user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{conn: log_in_user(conn, user), token: token, email: email, user: user}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")

      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"info" => message} = flash
      assert message == "Email changed."
      refute Accounts.get_user_by_email(user.email)
      assert Accounts.get_user_by_email(email)

      # use confirm token again
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "That email change link is invalid or has expired."
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/oops")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "That email change link is invalid or has expired."
      assert Accounts.get_user_by_email(user.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")
      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => message} = flash
      assert message == "You must log in to access this page."
    end
  end

  describe "passkeys" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "adding a passkey on this device lists it", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/users/settings")
      assert html =~ "No passkeys yet"
      assert has_element?(view, "#passkey-add[phx-hook='PasskeyRegister']")

      render_hook(view, "passkey:register_options", %{})
      assert_reply(view, %{challenge: challenge})

      response =
        registration_response(new_authenticator(), Base.url_decode64!(challenge, padding: false))

      html = render_hook(view, "passkey:register", response)
      assert html =~ "Passkey added."
      assert has_element?(view, "#passkeys li", "Added")
    end

    test "a bad registration says so and adds nothing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render_hook(view, "passkey:register_options", %{})
      assert_reply(view, _options)

      assert render_hook(view, "passkey:register", %{"attestationObject" => "%%%"}) =~
               "That didn&#39;t work. Please try again."

      assert render(view) =~ "No passkeys yet"
    end

    test "removing a passkey takes it off the list", %{conn: conn, user: user} do
      {key, _} = passkey_fixture(user, "Old phone")
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      assert has_element?(view, "#passkeys li", "Old phone")

      view |> element("#passkey-#{key.id} button", "Remove") |> render_click()
      refute has_element?(view, "#passkeys li", "Old phone")
    end
  end
end
