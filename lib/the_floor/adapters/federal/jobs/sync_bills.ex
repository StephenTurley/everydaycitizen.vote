defmodule TheFloor.Adapters.Federal.Jobs.SyncBills do
  @moduledoc """
  Lists bills updated since the last successful run and enqueues a `SyncBill`
  job for each. The listing starts 2 days before the cursor, so a bill whose
  detail job was discarded, or that offset paging skipped while update dates
  shifted, is listed again; re-syncing a bill is idempotent.

  The first run (no cursor) loads every bill from GovInfo's BILLSTATUS bulk zips
  instead of ~6 API requests per bill, then enqueues one `BackfillBillText`. An
  entry that fails to parse or write falls back to a `SyncBill` job. A missing
  zip (404, or GovInfo's HTML error page) is skipped, since a bill type may have
  no bills yet; a run that writes no bills at all fails, so the cursor stays unset
  and the next run tries the bulk path again. Bulk files lag the API by hours;
  the next run's 2-day overlap picks up what changed since.

  Snoozes until the congress session is stored and a members sync has succeeded
  (sponsorships need people).
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  require Logger

  alias TheFloor.Adapters.Federal.{BillWriter, Bulk, CongressGov, Job, Prerequisites}
  alias TheFloor.Adapters.Federal.Jobs.{BackfillBillText, SyncBill}
  alias TheFloor.Adapters.Federal.Normalize.BillStatus

  @overlap_seconds 2 * 86_400
  @bulk "https://www.govinfo.gov/bulkdata/BILLSTATUS"
  @types ~w(hr s hjres sjres hconres sconres hres sres)

  # The bulk load runs for minutes; it must end before Lifeline (2 h) would
  # treat it as orphaned and start it again.
  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(90)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    congress = args["congress"] || Application.fetch_env!(:the_floor, :federal)[:congress]

    with :ok <-
           Prerequisites.check(job, [
             Prerequisites.session(congress),
             Prerequisites.members_synced()
           ]) do
      sync(congress)
    end
  end

  defp sync(congress) do
    Job.run("sync_bills", fn
      run_id, nil -> bulk(congress, run_id)
      run_id, cursor -> list(congress, run_id, cursor)
    end)
  end

  defp list(congress, run_id, cursor) do
    params = [sort: "updateDate asc"] ++ from_param(cursor)

    count =
      "/bill/#{congress}"
      |> CongressGov.paginate("bills", params)
      |> Enum.reduce(0, fn {bill, _source}, n ->
        enqueue(congress, bill, run_id)
        n + 1
      end)

    {:ok, %{enqueued: count}}
  end

  defp bulk(congress, run_id) do
    stats =
      Enum.reduce(@types, %{source: "bulk", written: 0, fallback: 0, missing_zips: []}, fn type,
                                                                                           acc ->
        bulk_zip(congress, type, run_id, acc)
      end)

    case stats do
      {:error, _} = error ->
        error

      %{written: 0} ->
        {:error, :no_bulk_bills}

      stats ->
        Oban.insert!(BackfillBillText.new(%{"congress" => congress}))
        {:ok, stats}
    end
  end

  defp bulk_zip(_congress, _type, _run_id, {:error, _} = error), do: error

  defp bulk_zip(congress, type, run_id, acc) do
    url = "#{@bulk}/#{congress}/#{type}/BILLSTATUS-#{congress}-#{type}.zip"

    case Bulk.with_zip(
           url,
           &Bulk.reduce_entries(&1, acc, fn e, a -> entry(e, a, congress, run_id) end)
         ) do
      {:ok, acc} ->
        acc

      {:error, reason} when reason in [:not_a_zip, {:http_status, 404}] ->
        Logger.warning("sync_bills: no bulk zip at #{url}: #{inspect(reason)}")
        %{acc | missing_zips: [Path.basename(url) | acc.missing_zips]}

      {:error, reason} ->
        {:error, {:bulk_zip, Path.basename(url), reason}}
    end
  end

  # Any failure on one entry, raised or returned, falls back to the API for that
  # bill, so a single bad file never blocks the backfill.
  defp entry({name, xml, source}, acc, congress, run_id) do
    case write_entry(xml, source, run_id) do
      :ok ->
        %{acc | written: acc.written + 1}

      error ->
        Logger.warning("sync_bills: bulk entry #{name} failed (#{inspect(error)}); using the API")
        fallback(name, congress, run_id, acc)
    end
  end

  defp write_entry({:error, _} = error, _source, _run_id), do: error

  defp write_entry(xml, source, run_id) do
    with {:ok, parts} <- BillStatus.parse(xml),
         {:ok, _id} <- BillWriter.write(bulk_parts(parts, source), run_id) do
      :ok
    end
  rescue
    e -> {:exception, Exception.message(e)}
  end

  defp bulk_parts(parts, source) do
    %{
      detail: {parts.detail, source},
      subjects: parts.subjects,
      actions: {parts.actions, source},
      cosponsors: {parts.cosponsors, source},
      text: {parts.text, source}
    }
  end

  # `BILLSTATUS-119hr152.xml` names the bill when its contents cannot be read.
  defp fallback(name, congress, run_id, acc) do
    case Regex.run(~r/^BILLSTATUS-\d+([a-z]+)(\d+)\.xml$/, name) do
      [_, type, number] ->
        enqueue(congress, %{"type" => type, "number" => number}, run_id)
        %{acc | fallback: acc.fallback + 1}

      _ ->
        acc
    end
  end

  defp enqueue(congress, bill, run_id) do
    %{
      "congress" => congress,
      "type" => String.downcase(bill["type"]),
      "number" => to_string(bill["number"]),
      "run_id" => run_id
    }
    |> SyncBill.new()
    |> Oban.insert!()
  end

  defp from_param(nil), do: []

  defp from_param(%DateTime{} = cursor) do
    from = cursor |> DateTime.add(-@overlap_seconds) |> DateTime.truncate(:second)
    [fromDateTime: DateTime.to_iso8601(from)]
  end
end
