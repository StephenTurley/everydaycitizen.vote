defmodule EverydayCitizen.Adapters.Federal.Jobs.SyncHouseVote do
  @moduledoc """
  Fetches and stores one House roll-call vote (`congress`, `session`, `roll`):
  the vote detail plus its member positions.
  """
  use Oban.Worker, queue: :ingest, priority: 5, max_attempts: 5

  alias EverydayCitizen.Adapters.Federal.CongressGov
  alias EverydayCitizen.Adapters.Federal.Normalize.HouseVote
  alias EverydayCitizen.Ingest

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"congress" => c, "session" => s, "roll" => roll} = args}) do
    path = "/house-vote/#{c}/#{s}/#{roll}"

    # The members endpoint returns every member in one response, so no pagination.
    with {:ok, detail, _detail_source} <- CongressGov.get(path),
         {:ok, members, source} <- CongressGov.get(path <> "/members"),
         {:ok, _vote} <- Ingest.write(HouseVote.vote(detail, members, source), args["run_id"]) do
      :ok
    end
  end
end
