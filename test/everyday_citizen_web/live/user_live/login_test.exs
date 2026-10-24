defmodule EverydayCitizenWeb.UserLive.LoginTest do
  use EverydayCitizenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import EverydayCitizen.AccountsFixtures
  import EverydayCitizen.WebAuthnFixtures

  alias EverydayCitizen.Accounts

  # the fixture's own sign-in email is not the one under test
  defp clear_mailbox do
    receive do
      {:email, _} -> clear_mailbox()
    after
      0 -> :ok
    end
  end

  describe "sign-in page" do
    test "asks only for an email: there is no password", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Sign in"
      assert has_element?(view, ~s(input[type="email"]))
      refute has_element?(view, ~s(input[type="password"]))
      refute html =~ "assword"
    end
  end

  describe "emailed link" do
    test "an existing account gets a sign-in link", %{conn: conn} do
      user = user_fixture()
      clear_mailbox()
      {:ok, view, _html} = live(conn, ~p"/users/log-in")

      {:ok, _view, html} =
        view
        |> form("#login_form_magic", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Check your email for a link to sign in."

      assert EverydayCitizen.Repo.get_by!(Accounts.UserToken, user_id: user.id).context == "login"
      assert_email_sent(fn email -> email.subject == "Your sign-in link" end)
    end

    test "a new email gets an account and a link to confirm it, with the same reply", %{
      conn: conn
    } do
      email = unique_user_email()
      {:ok, view, _html} = live(conn, ~p"/users/log-in")

      {:ok, _view, html} =
        view
        |> form("#login_form_magic", user: %{email: email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Check your email for a link to sign in."
      assert %Accounts.User{confirmed_at: nil} = Accounts.get_user_by_email(email)

      assert_email_sent(fn sent ->
        sent.subject == "Confirm your account" and
          sent.from == {"Everyday Citizen", "hello@everydaycitizen.vote"}
      end)
    end

    test "the sign-in email carries only the link, no address or ZIP code", %{conn: conn} do
      user = user_fixture()
      clear_mailbox()
      conn = init_test_session(conn, %{district: "IA-1"})
      {:ok, view, _html} = live(conn, ~p"/users/log-in")
      view |> form("#login_form_magic", user: %{email: user.email}) |> render_submit()

      assert_email_sent(fn sent ->
        sent.text_body =~ "/users/log-in/" and not (sent.text_body =~ "IA-1")
      end)
    end

    test "an invalid email says so and sends nothing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/log-in")

      html =
        view
        |> form("#login_form_magic", user: %{email: "not an email"})
        |> render_submit()

      assert html =~ "must have the @ sign and no spaces"
      assert_no_email_sent()
    end
  end

  describe "re-confirming" do
    setup :register_and_log_in_user

    test "signed in, the email is fixed and the page asks to confirm", %{conn: conn, user: user} do
      {:ok, view, html} = live(conn, ~p"/users/log-in")
      assert html =~ "Confirm it&#39;s you"
      assert has_element?(view, ~s(input[readonly][value="#{user.email}"]))
    end
  end

  describe "passkey sign-in" do
    setup do
      user = user_fixture()
      {key, authenticator} = passkey_fixture(user)
      %{user: user, key: key, authenticator: authenticator}
    end

    defp start_passkey(view, for \\ "button") do
      render_hook(view, "passkey:auth_options", %{"for" => for})
      assert_reply(view, %{challenge: challenge, for: ^for})
      Base.url_decode64!(challenge, padding: false)
    end

    test "offers a passkey button and passkey autofill on the email field", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/log-in")
      assert has_element?(view, "#passkey-login[phx-hook='PasskeyLogin']")
      assert has_element?(view, "#passkey-sign-in[data-passkey-button]")
      assert has_element?(view, "#user_email[autocomplete='username webauthn']")
    end

    test "a verified passkey signs the person in on this device, tied to that passkey", %{
      conn: conn,
      user: user,
      key: key,
      authenticator: authenticator
    } do
      {:ok, view, _html} = live(conn, ~p"/users/log-in")
      challenge = start_passkey(view)
      render_hook(view, "passkey:auth", assertion_response(authenticator, challenge, 1))

      conn = follow_trigger_action(form(view, "#passkey_login_form"), conn)

      assert redirected_to(conn) == ~p"/"
      assert conn.resp_cookies["_everyday_citizen_web_user_remember_me"]
      {session_user, _} = Accounts.get_user_by_session_token(get_session(conn, :user_token))
      assert session_user.id == user.id
      assert session_user.session_key_id == key.id
    end

    test "the button and the autofill each keep their own challenge, used once", %{
      conn: conn,
      authenticator: authenticator
    } do
      {:ok, view, _html} = live(conn, ~p"/users/log-in")
      autofill = start_passkey(view, "autofill")
      _button = start_passkey(view, "button")

      response = assertion_response(authenticator, autofill, 1) |> Map.put("for", "autofill")
      render_hook(view, "passkey:auth", response)
      assert has_element?(view, "#passkey_login_form[phx-trigger-action]")

      assert render_hook(view, "passkey:auth", response) =~
               "That didn&#39;t work. Please try again."
    end

    test "an unknown or garbled passkey says the same thing and does not sign in", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/log-in")
      challenge = start_passkey(view)

      html =
        render_hook(view, "passkey:auth", assertion_response(new_authenticator(), challenge, 1))

      assert html =~ "couldn&#39;t sign you in with that passkey"

      start_passkey(view)

      assert render_hook(view, "passkey:auth", %{"rawId" => "%%%"}) =~
               "couldn&#39;t sign you in with that passkey"

      refute has_element?(view, "#passkey_login_form[phx-trigger-action]")
    end

    test "a browser without passkeys hides the button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/log-in")
      render_hook(view, "passkey:unsupported", %{})
      refute has_element?(view, "#passkey-sign-in")
    end
  end
end
