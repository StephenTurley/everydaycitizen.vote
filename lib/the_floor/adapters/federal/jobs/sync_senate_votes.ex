defmodule TheFloor.Adapters.Federal.Jobs.SyncSenateVotes do
  @moduledoc """
  Reads the Senate vote menu and enqueues `SyncSenateVote` for every roll not yet
  stored plus the most recent rolls (the menu has no update dates, so re-fetching
  the latest catches corrections). With a `session` arg only that session is read;
  otherwise every stored session of the congress is.
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  alias TheFloor.Adapters.Federal.{HTTP, Job}
  alias TheFloor.Adapters.Federal.Jobs.SyncSenateVote
  alias TheFloor.Adapters.Federal.Normalize.SenateVote
  alias TheFloor.{Legislature, Votes}

  @menu "https://www.senate.gov/legislative/LIS/roll_call_lists"
  @recent 10

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    congress = args["congress"] || Application.fetch_env!(:the_floor, :federal)[:congress]

    Job.run("sync_senate_votes", fn run_id, _cursor ->
      congress
      |> sessions(args["session"])
      |> Enum.reduce_while({:ok, %{}}, &accumulate(&1, &2, congress, run_id))
    end)
  end

  defp accumulate(session, {:ok, stats}, congress, run_id) do
    case sync_session(congress, session, run_id) do
      {:ok, session_stats} ->
        {:cont, {:ok, Map.put(stats, "#{congress}-#{session}", session_stats)}}

      {:error, _} = error ->
        {:halt, error}
    end
  end

  defp sessions(_congress, session) when not is_nil(session), do: [session]

  defp sessions(congress, nil) do
    "federal"
    |> Legislature.child_sessions("#{congress}")
    |> Enum.map(fn %{identifier: identifier} ->
      identifier |> String.split("-") |> List.last() |> String.to_integer()
    end)
  end

  defp sync_session(congress, session, run_id) do
    url = "#{@menu}/vote_menu_#{congress}_#{session}.xml"

    with {:ok, %{raw: raw}} <- HTTP.get(url, limiter: :senate_gov, decode: :raw) do
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
