defmodule EverydayCitizen.Jobs.DigestScheduler do
  @moduledoc """
  Runs at 07:00 in the site's zone (Oban cron): queues a `SendDigest` for each
  person with the daily email on who follows something. The jobs are unique per
  person and day, so running it twice queues nothing new.
  """
  use Oban.Worker, queue: :mail, max_attempts: 3

  alias EverydayCitizen.Accounts
  alias EverydayCitizen.Jobs.SendDigest

  @impl Oban.Worker
  def perform(_job) do
    date = EverydayCitizen.Clock.site_zone() |> EverydayCitizen.Clock.today() |> Date.to_iso8601()

    for user_id <- Accounts.digest_recipient_ids(),
        do: Oban.insert!(SendDigest.new(%{"user_id" => user_id, "date" => date}))

    :ok
  end
end
