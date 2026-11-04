defmodule EverydayCitizen.Adapters.Federal.Jobs.SyncCongress do
  @moduledoc """
  Bootstraps the federal jurisdiction, chambers and sessions for a congress.
  On the day a congress begins, Congress.gov may not list it yet (404): the job
  waits and tries again rather than failing.
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  alias EverydayCitizen.Adapters.Federal.{Congresses, CongressGov, Job}
  alias EverydayCitizen.Adapters.Federal.Normalize.Congress
  alias EverydayCitizen.Ingest

  @not_listed_snooze 6 * 3600

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    number = args["congress"] || Congresses.current()

    case CongressGov.get("/congress/#{number}") do
      {:error, {:http_status, 404}} -> {:snooze, @not_listed_snooze}
      fetched -> sync(fetched)
    end
  end

  defp sync(fetched) do
    Job.run("sync_congress", fn run_id, _cursor ->
      with {:ok, json, source} <- fetched,
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
