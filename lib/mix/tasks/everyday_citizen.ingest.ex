defmodule Mix.Tasks.EverydayCitizen.Ingest do
  @shortdoc "Enqueues the ingest jobs (all, or one by name)"
  @moduledoc """
  Enqueues the list-level ingest jobs of every configured adapter.

      mix everyday_citizen.ingest          # every job
      mix everyday_citizen.ingest bills    # one job by name

  Adapters are listed in `config :everyday_citizen, :ingest_adapters`; each exposes
  `all/0` returning `{name, worker, args}`. This task only enqueues: the jobs
  run in the application (`mix phx.server` or a release), which also runs the
  nightly schedule. Jobs run concurrently and may finish in any order; each one
  waits (snoozes) until the data it depends on is stored. In a release, use
  `EverydayCitizen.Release.ingest/1` instead.
  """
  use Mix.Task

  alias EverydayCitizen.Ingest.Jobs

  @impl Mix.Task
  def run(args) do
    Mix.EverydayCitizen.start_without_workers()

    name =
      case args do
        [] -> nil
        [name] -> name
        _ -> Mix.raise("usage: mix everyday_citizen.ingest [name]")
      end

    case Jobs.select(name) do
      {:ok, selected} ->
        for {name, job} <- Jobs.enqueue(selected) do
          Mix.shell().info("enqueued #{name} (job #{job.id})")
        end

      {:error, message} ->
        Mix.raise(message)
    end
  end
end
