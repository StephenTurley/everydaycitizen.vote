defmodule EverydayCitizen.Adapters.Federal.Jobs.SyncCongress do
  @moduledoc "Bootstraps the federal jurisdiction, chambers and sessions for a congress."
  use Oban.Worker, queue: :ingest, max_attempts: 3

  alias EverydayCitizen.Adapters.Federal.{CongressGov, Job}
  alias EverydayCitizen.Adapters.Federal.Normalize.Congress
  alias EverydayCitizen.Ingest

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    number = args["congress"] || Application.fetch_env!(:everyday_citizen, :federal)[:congress]

    Job.run("sync_congress", fn run_id, _cursor ->
      with {:ok, json, source} <- CongressGov.get("/congress/#{number}"),
           {:ok, count} <- write_all(Congress.records(json, source), run_id) do
        {:ok, %{records: count}}
      end
    end)
  end

  defp write_all(records, run_id) do
    Enum.reduce_while(records, {:ok, 0}, fn record, {:ok, n} ->
      case Ingest.write(record, run_id) do
        {:ok, _} -> {:cont, {:ok, n + 1}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
