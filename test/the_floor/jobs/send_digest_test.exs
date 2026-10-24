defmodule TheFloor.Jobs.SendDigestTest do
  # not async: one test swaps the mailer adapter in the application env
  use TheFloor.DataCase, async: false
  use Oban.Testing, repo: TheFloor.Repo

  import Swoosh.TestAssertions
  import TheFloor.AccountsFixtures

  alias TheFloor.Accounts.{Scope, User}
  alias TheFloor.{Follows, Repo}
  alias TheFloor.Jobs.{DigestScheduler, SendDigest}
  alias TheFloor.Legislation.{BillAction, BillVersion, Sponsorship}
  alias TheFloor.Votes.Vote

  @old ~U[2026-01-01 00:00:00.000000Z]

  defmodule FailingAdapter do
    @moduledoc false
    use Swoosh.Adapter
    def deliver(_email, _config), do: {:error, :mail_service_down}
  end

  setup do
    TheFloor.FloorFixtures.iowa!()

    for schema <- [BillAction, BillVersion, Vote, Sponsorship],
        do: Repo.update_all(schema, set: [inserted_at: @old])

    user = user_fixture()
    Repo.update_all(User, set: [inserted_at: ~U[2026-10-01 00:00:00Z]])
    flush_emails()
    bill = TheFloor.Legislation.get_bill("federal", "119-s-5")
    {:ok, _} = Follows.follow(Scope.for_user(user), {:bill, bill.id})
    %{user: Repo.reload!(user), bill: bill}
  end

  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end

  defp new_action!(bill, inserted_at \\ DateTime.utc_now()) do
    Repo.insert!(%BillAction{
      bill_id: bill.id,
      position: System.unique_integer([:positive]),
      date: ~D[2026-10-20],
      description: "Reported by the committee.",
      classification: "reported",
      source_id: bill.source_id,
      inserted_at: inserted_at
    })
  end

  # the cutoff is whole seconds; run a second after the test's changes were stored
  defp run(user, at \\ DateTime.add(DateTime.utc_now(), 1)) do
    perform_job(
      SendDigest,
      %{"user_id" => user.id, "date" => Date.to_iso8601(DateTime.to_date(at))},
      scheduled_at: at
    )
  end

  test "nothing changed: no email and the cutoff stays", %{user: user} do
    assert :ok = run(user)
    assert_no_email_sent()
    assert Repo.reload!(user).digest_sent_at == nil
  end

  test "a change: one email linking the bill, with one-click unsubscribe", %{
    user: user,
    bill: bill
  } do
    new_action!(bill)
    at = DateTime.add(DateTime.utc_now(:second), 1)
    assert :ok = run(user, at)

    assert_email_sent(fn email ->
      assert email.to == [{"", user.email}]
      assert email.from == {"Everyday Citizen", "hello@everydaycitizen.vote"}
      assert email.text_body =~ "S. 5"
      assert email.text_body =~ TheFloorWeb.Endpoint.url() <> "/bills/119-s-5"
      assert email.html_body =~ "/bills/119-s-5"

      assert [unsubscribe] =
               Regex.run(
                 ~r{<(https?://[^>]+/unsubscribe/[^>]+)>},
                 email.headers["List-Unsubscribe"],
                 capture: :all_but_first
               )

      assert email.text_body =~ unsubscribe
      assert email.headers["List-Unsubscribe-Post"] == "List-Unsubscribe=One-Click"
      true
    end)

    assert Repo.reload!(user).digest_sent_at == at
  end

  test "run again the same day: no second email", %{user: user, bill: bill} do
    new_action!(bill)
    at = DateTime.add(DateTime.utc_now(:second), 1)
    :ok = run(user, at)
    flush_emails()

    assert :ok = run(user, at)
    assert_no_email_sent()
  end

  test "a failed send keeps the cutoff so the next run covers it", %{user: user, bill: bill} do
    new_action!(bill)
    Application.put_env(:the_floor, :digest_mailer, adapter: FailingAdapter)
    on_exit(fn -> Application.delete_env(:the_floor, :digest_mailer) end)

    assert {:error, :mail_service_down} = run(user)
    assert Repo.reload!(user).digest_sent_at == nil
  end

  test "after a missed day the next email covers both days", %{user: user, bill: bill} do
    Repo.update!(
      Ecto.Changeset.change(user,
        digest_sent_at: DateTime.add(DateTime.utc_now(:second), -3, :day)
      )
    )

    new_action!(bill, DateTime.add(DateTime.utc_now(), -2, :day))
    new_action!(bill, DateTime.add(DateTime.utc_now(), -1, :hour))

    :ok = run(user)

    assert_email_sent(fn email ->
      assert length(Regex.scan(~r/Reported by the committee\./, email.text_body)) == 2
      true
    end)
  end

  test "never sent to someone with the daily email off", %{user: user, bill: bill} do
    Repo.update!(Ecto.Changeset.change(user, digest_enabled: false))
    new_action!(bill)
    assert :ok = run(user)
    assert_no_email_sent()
  end

  test "the 7:00 run queues one digest per person who follows something, once a day", %{
    user: user
  } do
    _not_following = user_fixture()
    off = user_fixture()
    Repo.update!(Ecto.Changeset.change(off, digest_enabled: false))

    {:ok, _} =
      Follows.follow(
        Scope.for_user(off),
        {:bill, TheFloor.Legislation.get_bill("federal", "119-s-5").id}
      )

    assert :ok = perform_job(DigestScheduler, %{})
    assert :ok = perform_job(DigestScheduler, %{})

    assert [job] = all_enqueued(worker: SendDigest)
    assert job.args["user_id"] == user.id
  end
end
