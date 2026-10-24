defmodule EverydayCitizen.Jobs.SendDigest do
  @moduledoc """
  Sends one person's daily email: the changes first stored after their last
  digest's cutoff (or since they joined) up to this run's cutoff, which is
  10 minutes before the job's scheduled time so rows still being written by
  an ingest transaction are left for the next email rather than lost. With
  nothing new it sends nothing and moves the cutoff on. With something new, the
  cutoff moves only after a successful send, so a failure is retried and a
  missed day is covered by the next email. One job per person per day (unique
  on `user_id` and `date`); a second run finds nothing after the new cutoff.
  """
  use Oban.Worker,
    queue: :mail,
    max_attempts: 5,
    unique: [keys: [:user_id, :date], period: :infinity, states: :all]

  alias EverydayCitizen.Accounts
  alias EverydayCitizen.Accounts.User
  alias EverydayCitizen.{Digest, Mailer}

  @lag_seconds 10 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}, scheduled_at: scheduled_at}) do
    cutoff = scheduled_at |> DateTime.truncate(:second) |> DateTime.add(-@lag_seconds)

    with %User{digest_enabled: true} = user <- Accounts.get_user(user_id),
         since = user.digest_sent_at || user.inserted_at,
         true <- DateTime.before?(since, cutoff) do
      send_or_advance(user, Digest.items(user, since, cutoff), cutoff)
    else
      _nothing_to_send -> :ok
    end
  end

  # nothing new: no email, and the next one starts from this cutoff
  defp send_or_advance(user, [], cutoff) do
    {:ok, _} = Accounts.put_digest_sent_at(user, cutoff)
    :ok
  end

  defp send_or_advance(user, items, cutoff), do: deliver(user, items, cutoff)

  defp deliver(user, items, cutoff) do
    email = Digest.Email.build(user, items)

    case Mailer.deliver(email, Application.get_env(:everyday_citizen, :mailer_overrides, [])) do
      {:ok, _} ->
        {:ok, _} = Accounts.put_digest_sent_at(user, cutoff)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
