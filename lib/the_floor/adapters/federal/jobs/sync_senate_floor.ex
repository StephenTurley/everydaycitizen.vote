defmodule TheFloor.Adapters.Federal.Jobs.SyncSenateFloor do
  @moduledoc """
  Fetches the senate.gov floor schedule page and writes one floor event per
  scheduled day. The page parser is unverified against the live page (see
  `Normalize.SenateFloor`). A page that fetched but parsed to no events logs a
  warning and records `items: 0` so coverage surfaces it. Fetch failures
  (including senate.gov's 403) fail the job for retry.
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  require Logger

  alias TheFloor.Adapters.Federal.{HTTP, Job}
  alias TheFloor.Adapters.Federal.Normalize.SenateFloor

  @url "https://www.senate.gov/legislative/schedule/floor_schedule.htm"

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    congress = args["congress"] || Application.fetch_env!(:the_floor, :federal)[:congress]

    Job.run("sync_senate_floor", fn run_id, _cursor -> sync(congress, run_id) end)
  end

  defp sync(congress, run_id) do
    with {:ok, %{raw: raw, source: source}} <- HTTP.get(@url, limiter: :senate_gov, decode: :raw),
         events = SenateFloor.events(raw, source, congress),
         :ok <- Job.write_events(events, run_id) do
      if events == [], do: Logger.warning("sync_senate_floor: page fetched but parsed to 0 items")
      {:ok, %{items: length(events)}}
    end
  end
end
