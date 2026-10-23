defmodule TheFloor.Adapters.Federal.Jobs.SyncBills do
  @moduledoc """
  Lists bills updated since the last successful run (all bills on the first run)
  and enqueues a `SyncBill` job for each. The listing starts 2 days before the
  cursor, so a bill whose detail job was discarded, or that offset paging skipped
  while update dates shifted, is listed again; re-syncing a bill is idempotent.
  Snoozes until the congress session and people are stored (sponsorships need
  people).
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  alias TheFloor.Adapters.Federal.{CongressGov, Job, Prerequisites}
  alias TheFloor.Adapters.Federal.Jobs.SyncBill

  @overlap_seconds 2 * 86_400

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    congress = args["congress"] || Application.fetch_env!(:the_floor, :federal)[:congress]

    with :ok <-
           Prerequisites.check(job, [Prerequisites.session(congress), Prerequisites.people()]) do
      sync(congress)
    end
  end

  defp sync(congress) do
    Job.run("sync_bills", fn run_id, cursor ->
      params = [sort: "updateDate asc"] ++ from_param(cursor)

      count =
        "/bill/#{congress}"
        |> CongressGov.paginate("bills", params)
        |> Enum.reduce(0, fn {bill, _source}, n ->
          enqueue(congress, bill, run_id)
          n + 1
        end)

      {:ok, %{enqueued: count}}
    end)
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
