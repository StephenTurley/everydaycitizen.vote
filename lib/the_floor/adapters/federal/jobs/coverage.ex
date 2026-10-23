defmodule TheFloor.Adapters.Federal.Jobs.Coverage do
  @moduledoc """
  Compares stored counts with the source's and records one check per name. A
  check whose source count cannot be fetched is recorded as failed (never
  raised), so one blocked source does not hide the others. Waits (snoozes) while
  other ingest jobs are still to run, so a full ingest is measured once it settles.
  """
  use Oban.Worker, queue: :ingest, max_attempts: 1

  alias TheFloor.Adapters.Federal.{Coverage, Job, Prerequisites}
  alias TheFloor.Ingest.Coverage, as: Checks

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    congress = args["congress"] || Application.fetch_env!(:the_floor, :federal)[:congress]

    with :ok <- Prerequisites.after_other_jobs(job, []), do: run(congress)
  end

  defp run(congress) do
    Job.run("coverage", fn run_id, _cursor ->
      results =
        for {name, expected_fun, actual_fun, tolerance} <- Coverage.checks(congress) do
          check(run_id, name, expected_fun, actual_fun, tolerance)
        end

      {:ok, %{checks: length(results), failed: Enum.count(results, &(not &1.passed))}}
    end)
  end

  defp check(run_id, name, expected_fun, actual_fun, tolerance) do
    case fetch_expected(expected_fun) do
      {:ok, expected} ->
        {:ok, row} = Checks.record(run_id, name, expected, actual_fun.(), tolerance)
        row

      {:error, reason} ->
        {:ok, row} = Checks.record_failure(run_id, name, tolerance, "expected count: #{reason}")
        row
    end
  end

  defp fetch_expected(fun) do
    case fun.() do
      {:ok, n} -> {:ok, n}
      {:error, reason} -> {:error, if(is_binary(reason), do: reason, else: inspect(reason))}
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  end
end
