defmodule EverydayCitizen.FeedbackTest do
  use EverydayCitizen.DataCase, async: false
  use Oban.Testing, repo: EverydayCitizen.Repo

  import Swoosh.TestAssertions
  import EverydayCitizen.AccountsFixtures

  alias EverydayCitizen.Feedback
  alias EverydayCitizen.Feedback.Report
  alias EverydayCitizen.Jobs.SendFeedbackEmail

  @attrs %{
    "kind" => "bill",
    "subject" => "bill:39:rfs",
    "prompt_version" => "v3",
    "summary" => "This bill would let partnerships settle.",
    "page" => "/bills/119-hr-10813",
    "reason" => "unclear",
    "note" => "What does 2.5 times mean?"
  }

  test "a report is stored with what was shown, and one email to the admin is queued" do
    assert {:ok, %Report{} = report} = Feedback.submit(@attrs, nil)
    assert report.summary == "This bill would let partnerships settle."
    assert report.user_id == nil
    assert [%{args: %{"report_id" => id}}] = all_enqueued(worker: SendFeedbackEmail)
    assert id == report.id
  end

  test "a signed-in reporter's account is linked" do
    user = user_fixture()
    assert {:ok, report} = Feedback.submit(@attrs, user)
    assert report.user_id == user.id
  end

  test "an unknown reason, kind or an overlong note is refused and nothing is queued" do
    for bad <- [
          %{"reason" => "spam"},
          %{"kind" => "elsewhere"},
          %{"note" => String.duplicate("x", 1_001)}
        ] do
      assert {:error, %Ecto.Changeset{}} = Feedback.submit(Map.merge(@attrs, bad), nil)
    end

    assert [] = all_enqueued(worker: SendFeedbackEmail)
  end

  test "the email tells the admin what was reported, where, and by whom" do
    user = user_fixture()
    # the account fixture's own sign-in email
    receive do: ({:email, _} -> :ok), after: (0 -> :ok)
    {:ok, report} = Feedback.submit(@attrs, user)

    assert :ok = perform_job(SendFeedbackEmail, %{"report_id" => report.id})

    assert_email_sent(fn email ->
      assert email.to == [{"", "admin@example.com"}]
      assert email.subject == "Feedback: unclear (bill summary)"
      assert email.text_body =~ "What does 2.5 times mean?"
      assert email.text_body =~ "This bill would let partnerships settle."
      assert email.text_body =~ EverydayCitizenWeb.Endpoint.url() <> "/bills/119-hr-10813"
      assert email.text_body =~ user.email
      assert email.text_body =~ "prompt v3"
    end)
  end

  test "with no admin address configured, nothing is sent" do
    {:ok, report} = Feedback.submit(@attrs, nil)
    Application.put_env(:everyday_citizen, :feedback_to, nil)
    on_exit(fn -> Application.put_env(:everyday_citizen, :feedback_to, "admin@example.com") end)

    assert :ok = perform_job(SendFeedbackEmail, %{"report_id" => report.id})
    refute_email_sent()
  end
end
