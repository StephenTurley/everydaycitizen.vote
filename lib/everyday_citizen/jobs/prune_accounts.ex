defmodule EverydayCitizen.Jobs.PruneAccounts do
  @moduledoc """
  Runs nightly (Oban cron): deletes expired sign-in tokens and accounts never
  confirmed after 30 days (`Accounts.prune/1`), so an email typed once and
  never used is not kept.
  """
  use Oban.Worker, queue: :mail, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    %{tokens: tokens, users: users} = EverydayCitizen.Accounts.prune()
    Logger.info("prune_accounts: #{tokens} expired tokens, #{users} unconfirmed accounts")
    :ok
  end
end
