defmodule TheFloor.Adapters.Federal.PrerequisitesTest do
  use TheFloor.DataCase, async: true
  use Oban.Testing, repo: TheFloor.Repo

  alias TheFloor.Adapters.Federal.Jobs.{Coverage, Relink, SyncBills, SyncHouseVotes, SyncMembers}
  alias TheFloor.Adapters.Federal.Prerequisites
  alias TheFloor.Provenance.IngestRun
  alias TheFloor.Repo

  test "list jobs snooze without recording a run when prerequisites are missing" do
    assert {:snooze, 300} = perform_job(SyncMembers, %{})
    assert {:snooze, 300} = perform_job(SyncBills, %{})
    assert {:snooze, 300} = perform_job(SyncHouseVotes, %{})
    assert Repo.aggregate(IngestRun, :count) == 0
  end

  test "a missing prerequisite becomes an error after 24 snoozes" do
    job = %Oban.Job{meta: %{"snoozed" => 23}}
    assert {:snooze, 300} = Prerequisites.check(job, [{:x, fn -> false end}])

    job = %Oban.Job{meta: %{"snoozed" => 24}}

    assert {:error, {:missing_prerequisite, :x}} =
             Prerequisites.check(job, [{:ok, fn -> true end}, {:x, fn -> false end}])

    assert :ok = Prerequisites.check(job, [{:ok, fn -> true end}])
  end

  test "after_other_jobs waits for other jobs in the queue, except ignored workers" do
    {:ok, relink} = Oban.insert(Relink.new(%{}))
    {:ok, coverage} = Oban.insert(Coverage.new(%{}))

    # Relink ignores coverage; coverage waits for relink.
    assert :ok = Prerequisites.after_other_jobs(relink, [Coverage])
    assert {:snooze, 300} = Prerequisites.after_other_jobs(coverage, [])

    # ...but not forever.
    assert :ok = Prerequisites.after_other_jobs(%{coverage | meta: %{"snoozed" => 24}}, [])
  end

  test "detail jobs are picked after list jobs" do
    for worker <- [
          TheFloor.Adapters.Federal.Jobs.SyncBill,
          TheFloor.Adapters.Federal.Jobs.SyncBillText,
          TheFloor.Adapters.Federal.Jobs.SyncHouseVote,
          TheFloor.Adapters.Federal.Jobs.SyncSenateVote,
          TheFloor.Adapters.Federal.Jobs.SyncCommitteeMeeting
        ] do
      assert %{changes: %{priority: 5}} = worker.new(%{})
    end

    priorities =
      TheFloor.Adapters.Federal.Jobs.all()
      |> TheFloor.Ingest.Mix.enqueue()
      |> Enum.map(fn {_name, job} -> job.priority end)

    assert Enum.max(priorities) <= 3
  end
end
