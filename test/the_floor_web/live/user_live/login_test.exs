defmodule TheFloorWeb.UserLive.LoginTest do
  use TheFloorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import TheFloor.AccountsFixtures

  alias TheFloor.Accounts

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

      assert TheFloor.Repo.get_by!(Accounts.UserToken, user_id: user.id).context == "login"
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
end
