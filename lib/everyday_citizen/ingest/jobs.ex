defmodule EverydayCitizen.Ingest.Jobs do
  @moduledoc """
  The ingest job list of every configured adapter, and enqueueing it. Shared by
  the `mix everyday_citizen.ingest` task and `EverydayCitizen.Release.ingest/1`.
  """

  @doc "Every configured adapter's `{name, worker, args}` jobs, in order."
  def all do
    :everyday_citizen |> Application.get_env(:ingest_adapters, []) |> Enum.flat_map(& &1.all())
  end

  @doc "Every configured adapter's jobs that run only by name."
  def on_demand do
    for adapter <- Application.get_env(:everyday_citizen, :ingest_adapters, []),
        Code.ensure_loaded?(adapter) and function_exported?(adapter, :on_demand, 0),
        job <- adapter.on_demand(),
        do: job
  end

  @doc """
  The jobs to run for an optional job name: all of them for `nil`, otherwise the
  one with that name. Returns `{:error, message}` for an unknown name.
  """
  def select(nil), do: {:ok, all()}

  def select(name) do
    jobs = all() ++ on_demand()

    case Enum.filter(jobs, &(elem(&1, 0) == name)) do
      [] ->
        names = Enum.map_join(jobs, ", ", &elem(&1, 0))
        {:error, "unknown job #{inspect(name)}; available: #{names}"}

      selected ->
        {:ok, selected}
    end
  end

  @doc """
  Inserts one Oban job per `{name, worker, args}`. Earlier entries get a higher
  priority (0..3; detail jobs use 5, so list jobs are picked first), but that only
  orders when jobs start, not when they finish: jobs enforce their own
  prerequisites. Returns `{name, job}` per inserted job.
  """
  def enqueue(jobs) do
    jobs
    |> Enum.with_index()
    |> Enum.map(fn {{name, worker, job_args}, index} ->
      {:ok, job} = Oban.insert(worker.new(job_args, priority: min(index, 3)))
      {name, job}
    end)
  end
end
