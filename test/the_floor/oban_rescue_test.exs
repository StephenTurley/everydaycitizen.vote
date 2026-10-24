defmodule TheFloor.ObanRescueTest do
  use TheFloor.DataCase, async: true

  alias TheFloor.ObanRescue

  defp job!(state, node) do
    %{}
    |> Oban.Job.new(worker: "TheFloor.Nightly.Check", queue: "ingest")
    |> Ecto.Changeset.change(
      state: state,
      attempted_by: node && [node, "producer-uuid"],
      attempted_at: node && DateTime.utc_now()
    )
    |> Repo.insert!()
  end

  test "jobs a previous deploy left executing are made available; this node's are left" do
    old = job!("executing", "old@1")
    mine = job!("executing", "me@1")
    waiting = job!("available", nil)

    assert ObanRescue.rescue_orphans("me@1") == 1

    assert Repo.reload!(old).state == "available"
    assert Repo.reload!(mine).state == "executing"
    assert Repo.reload!(waiting).state == "available"
  end
end
