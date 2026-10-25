defmodule EverydayCitizen.Adapters.Federal.Jobs.BackfillBillTitles do
  @moduledoc """
  Queues a `SyncBillTitles` job for every stored bill, so bills stored before
  titles were recorded get them (search matches on titles). Run by name
  (`bill_titles`); the jobs run one at a time on the `backfill` queue.
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  alias EverydayCitizen.Adapters.Federal.Job
  alias EverydayCitizen.Adapters.Federal.Jobs.SyncBillTitles
  alias EverydayCitizen.Legislation

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Job.run("backfill_bill_titles", fn _run_id, _cursor ->
      jobs =
        for id <- Legislation.bill_external_ids("federal"),
            [congress, type, number] <- [String.split(id, "-")],
            do:
              SyncBillTitles.new(%{
                congress: String.to_integer(congress),
                type: type,
                number: number
              })

      jobs |> Enum.chunk_every(1000) |> Enum.each(&Oban.insert_all/1)
      {:ok, %{"enqueued" => length(jobs)}}
    end)
  end
end
