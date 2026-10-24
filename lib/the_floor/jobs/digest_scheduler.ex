defmodule TheFloor.Jobs.DigestScheduler do
  @moduledoc """
  Runs at 07:00 America/New_York (Oban cron): queues a `SendDigest` for each
  person with the daily email on who follows something. The jobs are unique per
  person and day, so running it twice queues nothing new.
  """
  use Oban.Worker, queue: :mail, max_attempts: 3

  alias TheFloor.Accounts
  alias TheFloor.Jobs.SendDigest

  @zone "America/New_York"

  @impl Oban.Worker
  def perform(_job) do
    date = DateTime.now!(@zone) |> DateTime.to_date() |> Date.to_iso8601()

    for user_id <- Accounts.digest_recipient_ids(),
        do: Oban.insert!(SendDigest.new(%{"user_id" => user_id, "date" => date}))

    :ok
  end
end
