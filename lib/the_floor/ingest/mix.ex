defmodule TheFloor.Ingest.Mix do
  @moduledoc false
  # Shared setup for the ingest mix tasks.

  @doc """
  Starts the app with Oban's queues and plugins off, so a task that only
  enqueues jobs or reads results does not begin running them (or the nightly
  schedule) in a VM that is about to exit.
  """
  def start_without_workers do
    Mix.Task.run("app.config")
    oban = Application.fetch_env!(:the_floor, Oban)
    Application.put_env(:the_floor, Oban, Keyword.merge(oban, queues: false, plugins: false))
    Mix.Task.run("app.start")
  end

  @doc "Every configured adapter's `{name, worker, args}` jobs, in order."
  def jobs do
    :the_floor |> Application.get_env(:ingest_adapters, []) |> Enum.flat_map(& &1.all())
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
