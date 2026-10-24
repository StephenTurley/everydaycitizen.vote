defmodule Mix.Tasks.EverydayCitizen.Coverage do
  @shortdoc "Prints the latest coverage checks; exits non-zero if any fail"
  @moduledoc """
  Prints the most recent result of every coverage check
  (`name expected actual PASS|FAIL`) and exits with status 1 if any failed.
  A check whose source count could not be fetched shows `-` as expected and
  counts as a failure. Checks are produced by the `coverage` ingest job
  (`mix everyday_citizen.ingest coverage`). In a release, use
  `EverydayCitizen.Release.coverage/0` instead.
  """
  use Mix.Task

  alias EverydayCitizen.Ingest.Coverage

  @impl Mix.Task
  def run(_args) do
    Mix.EverydayCitizen.start_without_workers()

    checks = Coverage.latest()

    if checks == [] do
      Mix.raise("no coverage checks recorded; run: mix everyday_citizen.ingest coverage")
    end

    Mix.shell().info(Coverage.format_rows(checks))

    case Enum.count(checks, &(not &1.passed)) do
      0 -> :ok
      failed -> Mix.raise("#{failed} coverage check(s) failed")
    end
  end
end
