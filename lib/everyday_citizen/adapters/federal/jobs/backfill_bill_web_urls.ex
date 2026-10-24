defmodule EverydayCitizen.Adapters.Federal.Jobs.BackfillBillWebUrls do
  @moduledoc """
  Sets the official page for people (`web_url`) on bills stored before it was
  recorded. Each run handles `batch_size` bills (default 1000) and queues itself
  again while any remain. Run by name (`bill_web_urls`).
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  alias EverydayCitizen.Adapters.Federal.{BillId, Job}
  alias EverydayCitizen.Legislation

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    size = args["batch_size"] || 1000

    Job.run("backfill_bill_web_urls", fn _run_id, _cursor ->
      bills = Legislation.bills_without_web_url("federal", size)

      # a bill whose id builds no URL is marked with its source URL, so it is not retried
      for b <- bills,
          do: :ok = Legislation.put_web_url(b.id, BillId.web_url(b.external_id) || b.source_url)

      if length(bills) == size, do: Oban.insert!(new(args))
      {:ok, %{"filled" => length(bills)}}
    end)
  end
end
