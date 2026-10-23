defmodule TheFloor.Adapters.Federal.Jobs.SyncBills do
  @moduledoc """
  Lists bills updated since the last successful run (all bills on the first run)
  and enqueues a `SyncBill` job for each.
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  alias TheFloor.Adapters.Federal.{CongressGov, Job}
  alias TheFloor.Adapters.Federal.Jobs.SyncBill

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    congress = args["congress"] || Application.fetch_env!(:the_floor, :federal)[:congress]

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
    [fromDateTime: cursor |> DateTime.truncate(:second) |> DateTime.to_iso8601()]
  end
end
