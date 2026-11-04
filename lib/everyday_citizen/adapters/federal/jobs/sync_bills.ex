defmodule EverydayCitizen.Adapters.Federal.Jobs.SyncBills do
  @moduledoc """
  Lists bills updated since the last successful run and enqueues a `SyncBill`
  job for each. The listing starts 2 days before the cursor, so a bill whose
  detail job was discarded, or that offset paging skipped while update dates
  shifted, is listed again; re-syncing a bill is idempotent.

  The first run (no succeeded `sync_bills` yet) loads every bill from GovInfo's
  BILLSTATUS bulk zips instead of ~6 API requests per bill: it counts each type's
  zip and queues `BulkBillsChunk` jobs of `BulkBatch.chunk_size/0` bills, then
  waits (snoozes) until they finish (`Federal.BulkBatch`). Chunks skip bills
  already stored unchanged and fall back to `SyncBill` for unreadable entries. A
  missing zip is skipped (a bill type may have no bills yet). When every chunk is
  done it records `sync_bills` and enqueues `BackfillBillText`; a load that wrote
  no bills, or one whose chunk was discarded, fails, so the cursor stays unset and
  the next run loads again (cheaply: unchanged bills are skipped). Bulk files lag
  the API by hours; the next run's 2-day overlap picks up what changed since.

  Until 30 days after a new congress sits, the previous congress's bills are
  listed too (`Federal.Congresses.syncing/0`), so a bill passed in December
  still gets its signing or veto; the first-run bulk load covers only the
  sitting congress.

  Snoozes until the congress session is stored and a members sync has succeeded
  (sponsorships need people).
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  alias EverydayCitizen.Adapters.Federal.{BulkBatch, Congresses, CongressGov, Job, Prerequisites}
  alias EverydayCitizen.Adapters.Federal.Jobs.{BackfillBillText, BulkBillsChunk, SyncBill}
  alias EverydayCitizen.Provenance

  @overlap_seconds 2 * 86_400

  # Counting the zips takes minutes; it must end before Lifeline (2 h) would
  # treat the job as orphaned and start it again.
  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(90)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    congresses = if args["congress"], do: [args["congress"]], else: Congresses.syncing()
    congress = hd(congresses)

    with :ok <-
           Prerequisites.check(job, [
             Prerequisites.session(congress),
             Prerequisites.members_synced()
           ]) do
      sync(congresses)
    end
  end

  # The listings share one cursor: each lists what changed since the last run.
  defp sync([congress | _] = congresses) do
    case Provenance.last_succeeded_run("federal", "sync_bills") do
      nil ->
        bulk(congress)

      _ ->
        Job.run("sync_bills", fn run_id, cursor ->
          {:ok, Map.new(congresses, &{to_string(&1), list(&1, run_id, cursor)})}
        end)
    end
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

    %{enqueued: count}
  end

  # First run: the bulk load, as chunk jobs (`BulkBatch`). `sync_bills` is recorded
  # only once every chunk has finished, so the cursor is set only after a complete
  # load; until then each run of this job just waits for the chunks.
  defp bulk(congress) do
    BulkBatch.run(
      %{batch_job: "bulk_bills", chunk_job: "bulk_bills_chunk", chunk_worker: BulkBillsChunk},
      fn _batch -> BulkBillsChunk.chunks(congress) end,
      &finalize(congress, &1)
    )
  end

  defp finalize(congress, stats) do
    if Map.get(stats, "written", 0) + Map.get(stats, "unchanged", 0) == 0 do
      {:error, :no_bulk_bills}
    else
      Job.run("sync_bills", fn _run_id, _cursor ->
        Oban.insert!(BackfillBillText.new(%{"congress" => congress}))
        {:ok, Map.put(stats, "source", "bulk")}
      end)
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
