defmodule EverydayCitizenWeb.UserLive.LoginLimitsTest do
  # not async: the rate limiter's table and the mailer override are global
  use EverydayCitizenWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import EverydayCitizen.AccountsFixtures

  alias EverydayCitizen.Accounts

  defmodule FailingAdapter do
    @moduledoc false
    use Swoosh.Adapter
    def deliver(_email, _config), do: {:error, {401, "bad key"}}
  end

  setup do
    EverydayCitizen.RateLimit.reset()
    :ok
  end

  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end

  defp request_link(conn, email, ip \\ "203.0.113.7", spoof \\ "10.9.9.9") do
    # Fly appends the client's real address last; anything before it is the client's own
    conn = put_req_header(conn, "x-forwarded-for", "#{spoof}, #{ip}")
    {:ok, view, _html} = live(conn, ~p"/users/log-in")

    view
    |> form("#login_form_magic", user: %{email: email})
    |> render_submit()
  end

  defp emails_sent(n \\ 0) do
    receive do
      {:email, _} -> emails_sent(n + 1)
    after
      0 -> n
    end
  end

  test "one link a minute per email; the reply is the same either way", %{conn: conn} do
    user = user_fixture()
    flush_emails()

    for _ <- 1..2 do
      assert {:error, {:live_redirect, %{to: "/users/log-in", flash: flash}}} =
               request_link(conn, user.email)

      assert %{"info" => "Check your email for a link to sign in."} =
               Phoenix.LiveView.Utils.verify_flash(EverydayCitizenWeb.Endpoint, flash)
    end

    assert emails_sent() == 1
  end

  test "at most five links an hour per email", %{conn: conn} do
    user = user_fixture()
    flush_emails()

    for _ <- 1..5,
        do:
          {:ok, _} =
            EverydayCitizen.Repo.insert(%Accounts.UserToken{
              user_id: user.id,
              context: "login",
              token: :crypto.strong_rand_bytes(32),
              sent_to: user.email,
              inserted_at: DateTime.add(DateTime.utc_now(:second), -10, :minute)
            })

    request_link(conn, user.email)
    assert emails_sent() == 0
  end

  test "one visitor can ask for ten links an hour, then no more accounts or emails", %{conn: conn} do
    for i <- 1..10, do: request_link(conn, "person#{i}@example.com")
    assert emails_sent() == 10

    request_link(conn, "person11@example.com")
    assert emails_sent() == 0
    refute Accounts.get_user_by_email("person11@example.com")

    request_link(conn, "person12@example.com", "198.51.100.9")
    assert emails_sent() == 1
  end

  test "an email that fails to send says so", %{conn: conn} do
    Application.put_env(:everyday_citizen, :mailer_overrides, adapter: FailingAdapter)
    on_exit(fn -> Application.delete_env(:everyday_citizen, :mailer_overrides) end)

    html = request_link(conn, unique_user_email())
    assert html =~ "couldn&#39;t send the email"
    assert_no_email_sent()
  end

  test "a made-up forwarded address does not get around the visitor limit", %{conn: conn} do
    for i <- 1..10, do: request_link(conn, "p#{i}@example.com", "203.0.113.7", "1.1.1.#{i}")
    assert emails_sent() == 10

    request_link(conn, "p11@example.com", "203.0.113.7", "8.8.8.8")
    assert emails_sent() == 0
  end
end
