defmodule EverydayCitizen.Adapters.Federal.Jobs.BackfillBillSections do
  @moduledoc """
  Splits the stored text of versions saved before sections existed, or split by
  an older format of `BillSections` (`BillSections.format/0`). Each run handles
  `batch_size` versions (default 100, each holding its XML in memory) and queues
  itself again while any remain, so no single job runs long. Run by name
  (`bill_sections`). A version whose sections cannot be split or stored is logged
  and stored with none, so one bad document never stalls the rest.
  """
  use Oban.Worker, queue: :text, max_attempts: 3

  alias EverydayCitizen.Adapters.Federal.{BillSections, Job}
  alias EverydayCitizen.Legislation

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    size = args["batch_size"] || 100

    Job.run("backfill_bill_sections", fn _run_id, _cursor ->
      format = BillSections.format()
      versions = Legislation.versions_needing_sections(format, size)

      for v <- versions, do: :ok = split(v, format)

      if length(versions) == size, do: Oban.insert!(new(args))
      {:ok, %{"split" => length(versions)}}
    end)
  end

  defp split(v, format) do
    Legislation.put_sections(v.id, BillSections.sections_or_empty(v.xml), format)
  rescue
    exception ->
      Logger.warning(
        "backfill_bill_sections: version #{v.id} not split: #{Exception.message(exception)}"
      )

      Legislation.put_sections(v.id, [], format)
  end
end
