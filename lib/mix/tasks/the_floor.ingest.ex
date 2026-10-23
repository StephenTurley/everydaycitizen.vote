defmodule Mix.Tasks.TheFloor.Ingest do
  @shortdoc "Enqueues the ingest jobs (all, or one by name)"
  @moduledoc """
  Enqueues the list-level ingest jobs of every configured adapter.

      mix the_floor.ingest          # every job
      mix the_floor.ingest bills    # one job by name

  Adapters are listed in `config :the_floor, :ingest_adapters`; each exposes
  `all/0` returning `{name, worker, args}`. This task only enqueues: the jobs
  run in the application (`mix phx.server` or a release), which also runs the
  nightly schedule. Jobs run concurrently and may finish in any order; each one
  waits (snoozes) until the data it depends on is stored.
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    TheFloor.Ingest.Mix.start_without_workers()

    jobs = TheFloor.Ingest.Mix.jobs()

    selected =
      case args do
        [] -> jobs
        [name] -> Enum.filter(jobs, &(elem(&1, 0) == name))
        _ -> Mix.raise("usage: mix the_floor.ingest [name]")
      end

    if selected == [] do
      names = Enum.map_join(jobs, ", ", &elem(&1, 0))
      Mix.raise("unknown job #{inspect(hd(args))}; available: #{names}")
    end

    for {name, job} <- TheFloor.Ingest.Mix.enqueue(selected) do
      Mix.shell().info("enqueued #{name} (job #{job.id})")
    end
  end
end
