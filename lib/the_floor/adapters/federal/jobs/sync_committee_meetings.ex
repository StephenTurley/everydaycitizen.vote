defmodule TheFloor.Adapters.Federal.Jobs.SyncCommitteeMeetings do
  @moduledoc """
  Lists committee meetings of both chambers updated since 2 days before the cursor
  (the previous succeeded run's start; everything on the first run), so a meeting
  whose detail job was discarded or that paging skipped is listed again, and enqueues
  `SyncCommitteeMeeting` for each. Stored meetings dated within the next
  14 days are re-fetched on every run too, since meetings are rescheduled or
  canceled. Their chamber is read back from the stored source URL, because the
  listing is ordered by update date, not meeting date. Snoozes until the congress
  session and committees are stored, so meetings get their committee body.
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  alias TheFloor.Adapters.Federal.{CongressGov, Job, Prerequisites}
  alias TheFloor.Adapters.Federal.Jobs.SyncCommitteeMeeting
  alias TheFloor.Calendar

  @chambers ["house", "senate"]
  @upcoming_days 14
  @overlap_seconds 2 * 86_400

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    congress = args["congress"] || Application.fetch_env!(:the_floor, :federal)[:congress]
    checks = [Prerequisites.session(congress), Prerequisites.committees()]

    with :ok <- Prerequisites.check(job, checks), do: sync(congress)
  end

  defp sync(congress) do
    Job.run("sync_committee_meetings", fn run_id, cursor ->
      listed = Enum.flat_map(@chambers, &list(congress, &1, cursor))
      upcoming = upcoming(congress)
      wanted = Enum.uniq(listed ++ upcoming)

      wanted
      |> Enum.map(fn {chamber, event_id} ->
        SyncCommitteeMeeting.new(%{
          congress: congress,
          chamber: chamber,
          event_id: event_id,
          run_id: run_id
        })
      end)
      |> Oban.insert_all()

      {:ok, %{listed: length(listed), upcoming: length(upcoming), enqueued: length(wanted)}}
    end)
  end

  defp list(congress, chamber, cursor) do
    "/committee-meeting/#{congress}/#{chamber}"
    |> CongressGov.paginate("committeeMeetings", from_param(cursor))
    |> Enum.map(fn {item, _source} -> {chamber, item["eventId"]} end)
  end

  defp from_param(nil), do: []

  defp from_param(cursor) do
    from = cursor |> DateTime.add(-@overlap_seconds) |> DateTime.truncate(:second)
    [fromDateTime: DateTime.to_iso8601(from)]
  end

  defp upcoming(congress) do
    now = DateTime.utc_now()

    now
    |> Calendar.source_urls(DateTime.add(now, @upcoming_days * 86_400))
    |> Enum.flat_map(fn url ->
      case Regex.run(~r{/committee-meeting/#{congress}/(house|senate)/(\d+)}, url) do
        [_, chamber, event_id] -> [{chamber, event_id}]
        _ -> []
      end
    end)
  end
end
