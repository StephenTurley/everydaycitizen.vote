defmodule TheFloor.Adapters.Federal.Jobs.Relink do
  @moduledoc """
  Runs `TheFloor.Ingest.Relink` inside an ingest run: links votes to bills and
  positions to people that were stored after the vote. Waits (snoozes) while other
  ingest jobs other than coverage are still to run, so a full ingest links what its
  detail jobs wrote; runs nightly after the list jobs and before coverage.
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  alias TheFloor.Adapters.Federal.{Job, Prerequisites}
  alias TheFloor.Adapters.Federal.Jobs.Coverage
  alias TheFloor.Ingest.Relink

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    with :ok <- Prerequisites.after_other_jobs(job, [Coverage]) do
      Job.run("relink", fn _run_id, _cursor -> Relink.run() end)
    end
  end
end
