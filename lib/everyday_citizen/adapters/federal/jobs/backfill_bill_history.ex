defmodule EverydayCitizen.Adapters.Federal.Jobs.BackfillBillHistory do
  @moduledoc """
  Re-syncs every bill with two or more text versions, so bills stored before
  committee steps, related measures and amendments were recorded get them (the
  text history needs them only where the text changed). Run by name
  (`bill_history`); `SyncBill` jobs are unique per bill and rate limited.
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  alias EverydayCitizen.Adapters.Federal.Job
  alias EverydayCitizen.Adapters.Federal.Jobs.SyncBill
  alias EverydayCitizen.Legislation

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Job.run("backfill_bill_history", fn _run_id, _cursor ->
      jobs =
        for id <- Legislation.multi_version_bill_ids("federal"),
            [congress, type, number] <- [String.split(id, "-")],
            do: SyncBill.new(%{congress: String.to_integer(congress), type: type, number: number})

      Oban.insert_all(jobs)
      {:ok, %{"enqueued" => length(jobs)}}
    end)
  end
end
