defmodule EverydayCitizen.Accounts.UserNotifierTest do
  use EverydayCitizen.DataCase, async: true

  import EverydayCitizen.AccountsFixtures

  alias EverydayCitizen.Accounts.UserNotifier

  test "the sign-in email has a formatted version with the link, a plain one, and a reply-to" do
    user = user_fixture() |> Map.put(:confirmed_at, DateTime.utc_now())
    url = "https://everydaycitizen.vote/users/log-in/abc"

    {:ok, email} = UserNotifier.deliver_login_instructions(user, url)

    assert email.text_body =~ url
    assert email.html_body =~ ~s(href="#{url}")
    assert email.html_body =~ "Sign in"
    assert email.reply_to == {"", "replies@example.com"}
  end

  test "the account confirmation email does too" do
    user = %{user_fixture() | confirmed_at: nil}
    {:ok, email} = UserNotifier.deliver_login_instructions(user, "https://x.test/confirm")
    assert email.html_body =~ ~s(href="https://x.test/confirm")
    assert email.reply_to == {"", "replies@example.com"}
  end

  test "link text in the formatted version is escaped" do
    user = user_fixture() |> Map.put(:confirmed_at, DateTime.utc_now())
    {:ok, email} = UserNotifier.deliver_login_instructions(user, ~s(https://x.test/?a=1&b="2"))
    assert email.html_body =~ "a=1&amp;b=&quot;2&quot;"
  end
end
