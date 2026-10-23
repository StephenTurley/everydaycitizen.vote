defmodule TheFloor.Adapters.Federal.Jobs.SyncSenateVotes do
  @moduledoc """
  Reads the Senate vote menu for a session and enqueues `SyncSenateVote` for every
  roll not yet stored plus the most recent rolls (the menu has no update dates, so
  re-fetching the latest catches corrections).
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  alias TheFloor.Adapters.Federal.{HTTP, Job}
  alias TheFloor.Adapters.Federal.Jobs.SyncSenateVote
  alias TheFloor.Adapters.Federal.Normalize.SenateVote
  alias TheFloor.Votes

  @menu "https://www.senate.gov/legislative/LIS/roll_call_lists"
  @recent 10

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    congress = args["congress"] || Application.fetch_env!(:the_floor, :federal)[:congress]
    session = args["session"] || 1

    Job.run("sync_senate_votes", fn run_id, _cursor ->
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
    end)
  end

  defp rolls_to_fetch(rolls, congress, session) do
    stored =
      rolls |> Enum.map(&external_id(congress, session, &1)) |> Votes.existing_external_ids()

    recent = rolls |> Enum.sort(:desc) |> Enum.take(@recent)

    missing = Enum.reject(rolls, &MapSet.member?(stored, external_id(congress, session, &1)))

    (missing ++ recent) |> Enum.uniq() |> Enum.sort()
  end

  defp external_id(congress, session, roll), do: "senate-#{congress}-#{session}-#{roll}"
end
