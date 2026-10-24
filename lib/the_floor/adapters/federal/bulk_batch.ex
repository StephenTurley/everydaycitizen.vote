defmodule TheFloor.Adapters.Federal.BulkBatch do
  @moduledoc """
  Runs one bulk load as many small chunk jobs (queue `:bulk`) under a coordinator
  job that waits for them. A batch is an ingest run named `batch_job`, `:running`
  while its chunks work, so a later coordinator (a retry, or the next night's
  cron) joins the batch in progress instead of starting another.

  The coordinator calls `run/4` each time it executes:

    * no batch running: start one and insert the chunk jobs `fan_out.(batch_id)`
      returns (each chunk's args get `"batch"`), then snooze;
    * chunks still to run: snooze;
    * every chunk finished: sum the chunk runs' stats (each chunk records an
      ingest run named `chunk_job` whose stats carry `"batch"`), then call
      `finalize.(stats)`; a chunk that was discarded fails the batch, so the next
      coordinator run starts a fresh one (chunks skip work already done). With
      `tolerate_failed_chunks: true` the batch finalizes anyway, with the count in
      `stats["failed_chunks"]` (for loads that have their own fallback).

  Returns what the coordinator's `perform/1` returns.
  """
  import Ecto.Query

  alias TheFloor.Provenance
  alias TheFloor.Provenance.IngestRun
  alias TheFloor.Repo

  @adapter "federal"
  @wait_seconds 60
  @active ~w(available scheduled executing retryable)

  @type names :: %{batch_job: String.t(), chunk_job: String.t(), chunk_worker: module()}

  @spec run(
          names(),
          (integer() -> {:ok, [map()]} | {:error, term()}),
          (map() -> :ok | {:error, term()}),
          keyword()
        ) :: :ok | {:snooze, pos_integer()} | {:error, term()}
  def run(names, fan_out, finalize, opts \\ []) do
    case running_batch(names.batch_job) do
      nil -> start(names, fan_out, finalize)
      batch -> check(names, batch, finalize, opts[:tolerate_failed_chunks] == true)
    end
  end

  @doc "Size of one chunk: entries per chunk job."
  @spec chunk_size() :: pos_integer()
  def chunk_size, do: Application.get_env(:the_floor, :bulk_chunk_size, 1000)

  @doc "Chunk args `{offset, limit}` covering `count` entries."
  @spec slices(non_neg_integer()) :: [%{String.t() => non_neg_integer()}]
  def slices(count) do
    size = chunk_size()
    for offset <- 0..(count - 1)//size, count > 0, do: %{"offset" => offset, "limit" => size}
  end

  defp start(names, fan_out, finalize) do
    {:ok, batch} = Provenance.start_run(@adapter, names.batch_job)

    case fan_out.(batch.id) do
      {:ok, []} ->
        finish(batch, finalize, %{"chunks" => 0})

      {:ok, chunks} ->
        chunks
        |> Enum.map(&names.chunk_worker.new(Map.put(&1, "batch", batch.id)))
        |> Oban.insert_all()

        {:snooze, @wait_seconds}

      {:error, reason} = error ->
        {:ok, _} = Provenance.finish_run(batch, :failed, %{}, inspect(reason))
        error
    end
  end

  defp check(names, batch, finalize, tolerate_failed?) do
    states = chunk_states(names.chunk_worker, batch.id)
    failed = Enum.count(states, &(&1 in ["discarded", "cancelled"]))

    cond do
      Enum.any?(states, &(&1 in @active)) ->
        {:snooze, @wait_seconds}

      failed > 0 and not tolerate_failed? ->
        reason = {:bulk_chunks_failed, failed}
        {:ok, _} = Provenance.finish_run(batch, :failed, %{}, inspect(reason))
        {:error, reason}

      true ->
        stats =
          names.chunk_job
          |> chunk_stats(batch.id, length(states))
          |> Map.put("failed_chunks", failed)

        finish(batch, finalize, stats)
    end
  end

  defp finish(batch, finalize, stats) do
    case finalize.(stats) do
      :ok ->
        {:ok, _} = Provenance.finish_run(batch, :succeeded, stats, nil)
        :ok

      {:error, reason} = error ->
        {:ok, _} = Provenance.finish_run(batch, :failed, stats, inspect(reason))
        error
    end
  end

  defp running_batch(job) do
    IngestRun
    |> where([r], r.adapter == @adapter and r.job == ^job and r.status == :running)
    |> order_by([r], desc: r.id)
    |> limit(1)
    |> Repo.one()
  end

  defp chunk_states(worker, batch_id) do
    Oban.Job
    |> where([j], j.worker == ^inspect(worker))
    |> where([j], fragment("(?->>'batch')::bigint = ?", j.args, ^batch_id))
    |> select([j], j.state)
    |> Repo.all()
  end

  # Sums the integer stats of the batch's succeeded chunk runs.
  defp chunk_stats(chunk_job, batch_id, chunks) do
    IngestRun
    |> where([r], r.adapter == @adapter and r.job == ^chunk_job and r.status == :succeeded)
    |> where([r], fragment("(?->>'batch')::bigint = ?", r.stats, ^batch_id))
    |> select([r], r.stats)
    |> Repo.all()
    |> Enum.reduce(%{"chunks" => chunks}, fn stats, acc ->
      stats
      |> Map.drop(["batch"])
      |> Enum.filter(fn {_k, v} -> is_integer(v) end)
      |> Enum.reduce(acc, fn {k, v}, acc -> Map.update(acc, k, v, &(&1 + v)) end)
    end)
  end
end
