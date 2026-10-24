defmodule EverydayCitizen.Adapters.Federal.Job do
  @moduledoc """
  Wraps a list-level job in an ingest run: records start, passes the cursor
  (start of the last succeeded run), and records success or failure so a
  failed run never advances the cursor.
  """
  alias EverydayCitizen.Provenance

  @adapter "federal"

  @spec run(String.t(), (integer(), DateTime.t() | nil -> {:ok, map()} | {:error, term()})) ::
          :ok | {:error, term()}
  def run(job_name, fun) when is_function(fun, 2) do
    cursor =
      case Provenance.last_succeeded_run(@adapter, job_name) do
        nil -> nil
        run -> run.started_at
      end

    {:ok, run} = Provenance.start_run(@adapter, job_name)

    try do
      case fun.(run.id, cursor) do
        {:ok, stats} ->
          {:ok, _} = Provenance.finish_run(run, :succeeded, stats, nil)
          :ok

        {:error, reason} ->
          {:ok, _} = Provenance.finish_run(run, :failed, %{}, inspect(reason))
          {:error, reason}
      end
    rescue
      exception ->
        {:ok, _} = Provenance.finish_run(run, :failed, %{}, Exception.format(:error, exception))
        reraise exception, __STACKTRACE__
    end
  end

  @doc "Writes events in order inside a run; stops at the first failure."
  @spec write_events([EverydayCitizen.Ingest.Records.Event.t()], integer()) ::
          :ok | {:error, term()}
  def write_events(events, run_id) do
    Enum.reduce_while(events, :ok, fn event, :ok ->
      case EverydayCitizen.Ingest.write(event, run_id) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end
end
