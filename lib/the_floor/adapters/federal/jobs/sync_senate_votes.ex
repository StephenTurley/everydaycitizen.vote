defmodule TheFloor.Adapters.Federal.Jobs.SyncSenateVotes do
  @moduledoc """
  Reads the Senate vote menu and enqueues `SyncSenateVote` for every roll not yet
  stored plus the most recent rolls (the menu has no update dates, so re-fetching
  the latest catches corrections). With a `session` arg only that session is read;
  otherwise every stored session of the congress is. Snoozes until the congress has
  a stored session and people are stored.
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  alias TheFloor.Adapters.Federal.{HTTP, Job, Prerequisites, Sessions}
  alias TheFloor.Adapters.Federal.Jobs.SyncSenateVote
  alias TheFloor.Adapters.Federal.Normalize.SenateVote
  alias TheFloor.Votes

  @menu "https://www.senate.gov/legislative/LIS/roll_call_lists"
  @recent 10

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    congress = args["congress"] || Application.fetch_env!(:the_floor, :federal)[:congress]
    checks = [Prerequisites.child_sessions(congress), Prerequisites.people()]

    with :ok <- Prerequisites.check(job, checks), do: sync(congress, args)
  end

  defp sync(congress, args) do
    Job.run("sync_senate_votes", fn run_id, _cursor ->
      congress
      |> Sessions.numbers(args["session"])
      |> Sessions.reduce(congress, &sync_session(congress, &1, run_id))
    end)
  end

  @doc "URL of the vote menu for a session."
  @spec menu_url(integer(), integer()) :: String.t()
  def menu_url(congress, session), do: "#{@menu}/vote_menu_#{congress}_#{session}.xml"

  defp sync_session(congress, session, run_id) do
    with {:ok, %{raw: raw}} <-
           HTTP.get(menu_url(congress, session), limiter: :senate_gov, decode: :raw) do
      rolls = SenateVote.menu(raw)
      wanted = rolls_to_fetch(rolls, congress, session)

      wanted
      |> Enum.map(
        &SyncSenateVote.new(%{congress: congress, session: session, roll: &1, run_id: run_id})
      )
      |> Oban.insert_all()

      {:ok, %{menu: length(rolls), enqueued: length(wanted)}}
    end
  end

  defp rolls_to_fetch(rolls, congress, session) do
    stored =
      rolls
      |> Enum.map(&SenateVote.external_id(congress, session, &1))
      |> Votes.existing_external_ids()

    recent = rolls |> Enum.sort(:desc) |> Enum.take(@recent)

    missing =
      Enum.reject(rolls, &MapSet.member?(stored, SenateVote.external_id(congress, session, &1)))

    (missing ++ recent) |> Enum.uniq() |> Enum.sort()
  end
end
