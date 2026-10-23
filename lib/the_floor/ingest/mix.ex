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
end
