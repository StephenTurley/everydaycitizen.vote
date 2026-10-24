defmodule EverydayCitizen.Adapters.Federal.Prerequisites do
  @moduledoc """
  Gates list jobs on the data they depend on. On a first full ingest the list jobs
  start together, so a job whose prerequisites are not stored yet snoozes
  (`{:snooze, 300}`) instead of running on partial data. The check happens before
  `Federal.Job.run/2`, so a snoozed attempt records no ingest run and does not move
  the cursor.

  Snoozing is bounded: after 24 snoozes (~2 h) a missing prerequisite becomes
  `{:error, {:missing_prerequisite, name}}` so Oban retries and eventually discards
  it, and a job waiting for other ingest jobs (`after_other_jobs/2`) runs anyway.
  """
  import Ecto.Query

  alias EverydayCitizen.Adapters.Federal.Sessions
  alias EverydayCitizen.Legislature
  alias EverydayCitizen.Provenance
  alias EverydayCitizen.Repo

  @snooze_seconds 300
  @max_snoozes 24
  @active ~w(available scheduled retryable executing)

  @type check :: {atom(), (-> boolean())}

  @doc "`:ok` when every check holds, else a snooze (or an error once snoozed too often)."
  @spec check(Oban.Job.t(), [check()]) :: :ok | {:snooze, pos_integer()} | {:error, term()}
  def check(%Oban.Job{} = job, checks) do
    case Enum.find(checks, fn {_name, fun} -> not fun.() end) do
      nil -> :ok
      {name, _} -> if snoozes(job) < @max_snoozes, do: snooze(), else: missing(name)
    end
  end

  @doc """
  Snoozes while any other job in the job's queue is still to run or running, except
  workers in `ignore`; runs anyway once snoozed too often.
  """
  @spec after_other_jobs(Oban.Job.t(), [module()]) :: :ok | {:snooze, pos_integer()}
  def after_other_jobs(%Oban.Job{} = job, ignore) do
    ignore = Enum.map(ignore, &inspect/1)

    busy? =
      Oban.Job
      |> where([j], j.queue == ^job.queue and j.id != ^job.id and j.state in @active)
      |> where([j], j.worker not in ^ignore)
      |> Repo.exists?()

    if busy? and snoozes(job) < @max_snoozes, do: snooze(), else: :ok
  end

  @doc "The congress session is stored."
  @spec session(integer()) :: check()
  def session(congress),
    do: {:session, fn -> Legislature.get_session("federal", "#{congress}") != nil end}

  @doc "At least one session of the congress is stored."
  @spec child_sessions(integer()) :: check()
  def child_sessions(congress),
    do: {:child_sessions, fn -> Sessions.numbers(congress, nil) != [] end}

  @doc "At least one person is stored."
  @spec people() :: check()
  def people, do: {:people, &Legislature.any_person?/0}

  @doc """
  A members sync has succeeded, so every member a bill can reference is stored
  (sponsorships of people not yet stored are skipped, not deferred).
  """
  @spec members_synced() :: check()
  def members_synced,
    do:
      {:members_synced, fn -> Provenance.last_succeeded_run("federal", "sync_members") != nil end}

  @doc "At least one committee is stored."
  @spec committees() :: check()
  def committees,
    do: {:committees, fn -> Legislature.any_body?("federal", ~w(committee subcommittee)) end}

  defp snoozes(%Oban.Job{meta: meta}), do: (meta || %{})["snoozed"] || 0
  defp snooze, do: {:snooze, @snooze_seconds}
  defp missing(name), do: {:error, {:missing_prerequisite, name}}
end
