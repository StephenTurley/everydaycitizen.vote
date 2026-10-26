defmodule EverydayCitizen.Jobs.PruneAccountsTest do
  use EverydayCitizen.DataCase, async: true
  use Oban.Testing, repo: EverydayCitizen.Repo

  import EverydayCitizen.AccountsFixtures

  alias EverydayCitizen.Accounts.{User, UserToken}
  alias EverydayCitizen.Jobs.PruneAccounts
  alias EverydayCitizen.Repo

  defp token!(user, context, age_seconds) do
    Repo.insert!(%UserToken{
      token: :crypto.strong_rand_bytes(32),
      context: context,
      sent_to: user.email,
      user_id: user.id,
      inserted_at: DateTime.add(DateTime.utc_now(:second), -age_seconds)
    })
  end

  defp contexts(user),
    do:
      Repo.all(from t in UserToken, where: t.user_id == ^user.id, select: t.context)
      |> Enum.sort()

  test "expired sign-in tokens are deleted; ones still valid are kept" do
    user = user_fixture()
    Repo.delete_all(UserToken)

    token!(user, "login", 20 * 60)
    token!(user, "login", 5 * 60)
    token!(user, "change:old@example.com", 8 * 86_400)
    token!(user, "change:old@example.com", 86_400)
    token!(user, "session", 15 * 86_400)
    token!(user, "session", 86_400)
    token!(user, "passkey_login", 120)
    token!(user, "passkey_login", 10)

    assert :ok = perform_job(PruneAccounts, %{})

    assert contexts(user) == ["change:old@example.com", "login", "passkey_login", "session"]
  end

  test "an account never confirmed is deleted after 30 days; a confirmed one never is" do
    stale = unconfirmed_user_fixture()
    fresh = unconfirmed_user_fixture()
    confirmed = user_fixture()

    for user <- [stale, confirmed] do
      Repo.update_all(from(u in User, where: u.id == ^user.id),
        set: [inserted_at: DateTime.add(DateTime.utc_now(:second), -31 * 86_400)]
      )
    end

    assert :ok = perform_job(PruneAccounts, %{})

    assert Repo.get(User, stale.id) == nil
    assert Repo.get(User, fresh.id)
    assert Repo.get(User, confirmed.id)
  end

  test "runs nightly" do
    {Oban.Plugins.Cron, opts} =
      Application.fetch_env!(:everyday_citizen, Oban)[:plugins]
      |> Enum.find(&match?({Oban.Plugins.Cron, _}, &1))

    assert Enum.any?(opts[:crontab], &match?({_, PruneAccounts}, &1))
  end
end
