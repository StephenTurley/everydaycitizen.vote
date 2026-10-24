defmodule EverydayCitizen.ObanRescueTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.ObanRescue

  defp job!(state, node) do
    %{}
    |> Oban.Job.new(worker: "EverydayCitizen.Nightly.Check", queue: "ingest")
    |> Ecto.Changeset.change(
      state: state,
      attempted_by: node && [node, "producer-uuid"],
      attempted_at: node && DateTime.utc_now()
    )
    |> Repo.insert!()
  end

  test "jobs an earlier deploy of this machine left executing are made available; others are left" do
    earlier = job!("executing", "m1-git-aaa")
    mine = job!("executing", "m1-git-bbb")
    other_machine = job!("executing", "m2-git-aaa")
    waiting = job!("available", nil)

    assert ObanRescue.rescue_orphans("m1-git-bbb") == 1

    assert Repo.reload!(earlier).state == "available"
    assert Repo.reload!(mine).state == "executing"
    assert Repo.reload!(other_machine).state == "executing"
    assert Repo.reload!(waiting).state == "available"
  end
end
