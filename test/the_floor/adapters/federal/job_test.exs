defmodule TheFloor.Adapters.Federal.JobTest do
  use TheFloor.DataCase, async: true

  alias TheFloor.Adapters.Federal.Job
  alias TheFloor.Provenance
  alias TheFloor.Provenance.IngestRun
  alias TheFloor.Repo

  test "success records a succeeded run with stats and passes the cursor" do
    assert :ok = Job.run("t_ok", fn _id, nil -> {:ok, %{n: 1}} end)
    run = Provenance.last_succeeded_run("federal", "t_ok")
    assert run.stats == %{"n" => 1}

    test_pid = self()

    assert :ok =
             Job.run("t_ok", fn _id, cursor ->
               send(test_pid, {:cursor, cursor})
               {:ok, %{}}
             end)

    assert_received {:cursor, %DateTime{} = cursor}
    assert cursor == run.started_at
  end

  test "failed run does not advance cursor" do
    assert :ok = Job.run("t_fail", fn _id, _ -> {:ok, %{}} end)
    good = Provenance.last_succeeded_run("federal", "t_fail")

    assert {:error, :boom} = Job.run("t_fail", fn _id, _ -> {:error, :boom} end)

    failed = Repo.get_by!(IngestRun, job: "t_fail", status: :failed)
    assert failed.error == ":boom"
    assert Provenance.last_succeeded_run("federal", "t_fail").id == good.id
  end

  test "raise records failure and re-raises" do
    assert_raise RuntimeError, "kaboom", fn ->
      Job.run("t_raise", fn _id, _ -> raise "kaboom" end)
    end

    failed = Repo.get_by!(IngestRun, job: "t_raise", status: :failed)
    assert failed.error =~ "kaboom"
    assert Provenance.last_succeeded_run("federal", "t_raise") == nil
  end
end
