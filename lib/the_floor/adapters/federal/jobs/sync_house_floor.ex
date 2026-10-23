defmodule TheFloor.Adapters.Federal.Jobs.SyncHouseFloor do
  @moduledoc """
  Fetches the House floor schedule (docs.house.gov weekly XML) for the Monday of
  the current and the next week (Eastern time) and writes one floor event per item.

  docs.house.gov answers 200 with an HTML page (and 404 in places) for a week with
  no published schedule; both mean no events and the job succeeds. A week that
  fetched as XML but parsed to no events logs a warning and counts as `items: 0`.
  The optional `date` arg (ISO date) replaces today, for tests and backfills.
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  require Logger

  alias TheFloor.Adapters.Federal.{HTTP, Job}
  alias TheFloor.Adapters.Federal.Normalize.HouseFloor

  @base "https://docs.house.gov/floor/Download.aspx?file=/billsthisweek"

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    congress = args["congress"] || Application.fetch_env!(:the_floor, :federal)[:congress]

    Job.run("sync_house_floor", fn run_id, _cursor ->
      args |> today() |> mondays() |> sync(congress, run_id)
    end)
  end

  defp today(%{"date" => iso}), do: Date.from_iso8601!(iso)
  defp today(_args), do: "America/New_York" |> DateTime.now!() |> DateTime.to_date()

  defp mondays(date) do
    monday = Date.beginning_of_week(date, :monday)
    [monday, Date.add(monday, 7)]
  end

  defp sync(mondays, congress, run_id) do
    Enum.reduce_while(mondays, {:ok, %{weeks: 0, items: 0}}, fn monday, {:ok, stats} ->
      case sync_week(monday, congress, run_id) do
        :missing -> {:cont, {:ok, stats}}
        {:ok, count} -> {:cont, {:ok, %{weeks: stats.weeks + 1, items: stats.items + count}}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp sync_week(monday, congress, run_id) do
    stamp = Calendar.strftime(monday, "%Y%m%d")

    case HTTP.get("#{@base}/#{stamp}/#{stamp}.xml", limiter: :house_docs, decode: :raw) do
      {:ok, %{raw: raw, source: source}} ->
        if HTTP.html?(raw), do: :missing, else: store(raw, source, stamp, congress, run_id)

      {:error, {:http_status, 404}} ->
        :missing

      {:error, _} = error ->
        error
    end
  end

  defp store(raw, source, stamp, congress, run_id) do
    events = HouseFloor.events(raw, source, congress)

    if events == [] do
      Logger.warning("sync_house_floor: schedule for week #{stamp} fetched but parsed to 0 items")
    end

    with :ok <- Job.write_events(events, run_id), do: {:ok, length(events)}
  end
end
