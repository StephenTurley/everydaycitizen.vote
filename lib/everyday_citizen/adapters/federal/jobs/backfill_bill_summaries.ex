defmodule EverydayCitizen.Adapters.Federal.Jobs.BackfillBillSummaries do
  @moduledoc """
  Fills the official summaries of bills already stored, from the BILLSTATUS bulk
  zips, as `BulkBillsChunk` jobs in summaries-only mode (`Federal.BulkBatch`).
  Bills loaded before summaries were stored are otherwise skipped as unchanged
  until their source next changes. Run by name (`bill_summaries`).
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  alias EverydayCitizen.Adapters.Federal.{BulkBatch, Job}
  alias EverydayCitizen.Adapters.Federal.Jobs.BulkBillsChunk

  # Counting the zips takes minutes; it must end before Lifeline (2 h) would
  # treat the job as orphaned and start it again.
  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(90)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    congress = args["congress"] || Application.fetch_env!(:everyday_citizen, :federal)[:congress]

    BulkBatch.run(
      %{
        batch_job: "bulk_bill_summaries",
        chunk_job: "bulk_bills_chunk",
        chunk_worker: BulkBillsChunk
      },
      fn _batch ->
        with {:ok, chunks} <- BulkBillsChunk.chunks(congress),
             do: {:ok, Enum.map(chunks, &Map.put(&1, "only", "summaries"))}
      end,
      fn stats ->
        Job.run("backfill_bill_summaries", fn _run_id, _cursor -> {:ok, stats} end)
      end
    )
  end
end
