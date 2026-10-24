defmodule EverydayCitizen.Adapters.Federal.Jobs.BackfillBillText do
  @moduledoc """
  Loads bill version text from GovInfo's BILLS bulk zips (one per session and
  bill type) instead of one request per version: it counts each zip and queues
  `BulkBillTextChunk` jobs, then waits (snoozes) until they finish
  (`Federal.BulkBatch`). A zip that cannot be fetched only loses its chunks: once
  every chunk is done, each version still missing text gets a `SyncBillText` job,
  so text the bulk files lack, or that failed to load, still arrives.
  """
  use Oban.Worker, queue: :text, max_attempts: 3

  require Logger

  alias EverydayCitizen.Adapters.Federal.{Bulk, BulkBatch, Job, Sessions}
  alias EverydayCitizen.Adapters.Federal.Jobs.{BulkBillTextChunk, SyncBillText}
  alias EverydayCitizen.Legislation

  @types ~w(hr s hjres sjres hconres sconres hres sres)

  # Counting the zips takes minutes; it must end before Lifeline (2 h) would
  # treat the job as orphaned and start it again.
  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(90)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    congress = args["congress"] || Application.fetch_env!(:everyday_citizen, :federal)[:congress]

    BulkBatch.run(
      %{
        batch_job: "bulk_bill_text",
        chunk_job: "bulk_bill_text_chunk",
        chunk_worker: BulkBillTextChunk
      },
      fn _batch -> {:ok, fan_out(congress)} end,
      &finalize/1,
      tolerate_failed_chunks: true
    )
  end

  # A zip that cannot be counted contributes no chunks; its versions fall back.
  defp fan_out(congress) do
    for session <- Sessions.numbers(congress, nil), type <- @types, reduce: [] do
      chunks ->
        url = BulkBillTextChunk.zip_url(congress, session, type)

        case Bulk.with_zip(url, &Bulk.count_entries/1) do
          {:ok, count} ->
            extra = %{"congress" => congress, "session" => session, "type" => type}
            chunks ++ Enum.map(BulkBatch.slices(count), &Map.merge(&1, extra))

          {:error, reason} ->
            Logger.warning("backfill_bill_text: skipped #{url}: #{inspect(reason)}")
            chunks
        end
    end
  end

  defp finalize(stats) do
    Job.run("backfill_bill_text", fn _run_id, _cursor ->
      missing = Legislation.version_keys_missing_text("federal")

      for {bill_id, code} <- missing do
        Oban.insert!(SyncBillText.new(%{"bill_external_id" => bill_id, "code" => code}))
      end

      {:ok, Map.put(stats, "fallback", length(missing))}
    end)
  end
end
