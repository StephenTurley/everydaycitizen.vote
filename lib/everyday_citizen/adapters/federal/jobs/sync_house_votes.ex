defmodule EverydayCitizen.Adapters.Federal.Jobs.SyncHouseVotes do
  @moduledoc """
  Lists House roll-call votes and enqueues `SyncHouseVote` for every roll not yet
  stored plus every roll whose source `updateDate` is at or after the cursor (the
  previous succeeded run's start), so corrections are re-fetched. With a `session`
  arg only that session is read; otherwise every stored session of the congress is.
  Snoozes until the congress has a stored session and people are stored.
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  alias EverydayCitizen.Adapters.Federal.{CongressGov, Job, Prerequisites, Sessions}
  alias EverydayCitizen.Adapters.Federal.Jobs.SyncHouseVote
  alias EverydayCitizen.Adapters.Federal.Normalize.HouseVote
  alias EverydayCitizen.Votes

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    congress = args["congress"] || Application.fetch_env!(:everyday_citizen, :federal)[:congress]
    checks = [Prerequisites.child_sessions(congress), Prerequisites.people()]

    with :ok <- Prerequisites.check(job, checks), do: sync(congress, args)
  end

  defp sync(congress, args) do
    Job.run("sync_house_votes", fn run_id, cursor ->
      congress
      |> Sessions.numbers(args["session"])
      |> Sessions.reduce(congress, &sync_session(congress, &1, run_id, cursor))
    end)
  end

  defp sync_session(congress, session, run_id, cursor) do
    items =
      "/house-vote/#{congress}/#{session}"
      |> CongressGov.paginate("houseRollCallVotes")
      |> Enum.flat_map(fn {item, _source} ->
        HouseVote.list(%{"houseRollCallVotes" => [item]})
      end)

    wanted = rolls_to_fetch(items, congress, session, cursor)

    wanted
    |> Enum.map(
      &SyncHouseVote.new(%{congress: congress, session: session, roll: &1, run_id: run_id})
    )
    |> Oban.insert_all()

    {:ok, %{listed: length(items), enqueued: length(wanted)}}
  end

  defp rolls_to_fetch(items, congress, session, cursor) do
    stored =
      items
      |> Enum.map(&HouseVote.external_id(congress, session, &1.roll))
      |> Votes.existing_external_ids()

    items
    |> Enum.filter(fn %{roll: roll, updated_at: updated_at} ->
      not MapSet.member?(stored, HouseVote.external_id(congress, session, roll)) or
        updated_since?(updated_at, cursor)
    end)
    |> Enum.map(& &1.roll)
    |> Enum.sort()
  end

  defp updated_since?(updated_at, cursor) when is_nil(updated_at) or is_nil(cursor), do: false
  defp updated_since?(updated_at, cursor), do: DateTime.compare(updated_at, cursor) != :lt
end
