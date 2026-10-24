defmodule TheFloor.Adapters.Federal.Jobs.BackfillBillSections do
  @moduledoc """
  Splits the stored text of versions saved before sections existed. Each run
  handles `batch_size` versions (default 500) and queues itself again while any
  remain, so no single job runs long. Run by name (`bill_sections`).
  """
  use Oban.Worker, queue: :text, max_attempts: 3

  alias TheFloor.Adapters.Federal.{BillSections, Job}
  alias TheFloor.Legislation

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    size = args["batch_size"] || 500

    Job.run("backfill_bill_sections", fn _run_id, _cursor ->
      versions = Legislation.versions_without_sections(size)

      for v <- versions,
          do: :ok = Legislation.put_sections(v.id, BillSections.sections_or_empty(v.xml))

      if length(versions) == size, do: Oban.insert!(new(args))
      {:ok, %{"split" => length(versions)}}
    end)
  end
end
