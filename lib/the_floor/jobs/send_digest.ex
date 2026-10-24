defmodule TheFloor.Jobs.SendDigest do
  @moduledoc """
  Sends one person's daily email: the changes first stored after their last
  digest's cutoff (or since they joined) up to this job's scheduled time. With
  nothing new it sends nothing and keeps the cutoff. The cutoff moves to the
  scheduled time only after a successful send, so a failure is retried and a
  missed day is covered by the next email. One job per person per day (unique
  on `user_id` and `date`); a second run finds nothing after the new cutoff.
  """
  use Oban.Worker,
    queue: :mail,
    max_attempts: 5,
    unique: [keys: [:user_id, :date], period: :infinity, states: :all]

  alias TheFloor.Accounts
  alias TheFloor.Accounts.User
  alias TheFloor.{Digest, Mailer}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}, scheduled_at: scheduled_at}) do
    cutoff = DateTime.truncate(scheduled_at, :second)

    with %User{digest_enabled: true} = user <- Accounts.get_user(user_id),
         since = user.digest_sent_at || user.inserted_at,
         true <- DateTime.before?(since, cutoff),
         [_ | _] = items <- Digest.items(user, since, cutoff) do
      deliver(user, items, cutoff)
    else
      _nothing_to_send -> :ok
    end
  end

  defp deliver(user, items, cutoff) do
    email = Digest.Email.build(user, items)

    case Mailer.deliver(email, Application.get_env(:the_floor, :digest_mailer, [])) do
      {:ok, _} ->
        {:ok, _} = Accounts.put_digest_sent_at(user, cutoff)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
