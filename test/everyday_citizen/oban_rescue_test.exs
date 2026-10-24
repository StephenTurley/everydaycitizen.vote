defmodule EverydayCitizen.ObanRescueTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.ObanRescue

  @now ~U[2026-10-24 18:00:00.000000Z]

  defp job!(state, node, attempted_ago_seconds) do
    %{}
    |> Oban.Job.new(worker: "EverydayCitizen.Nightly.Check", queue: "ingest")
    |> Ecto.Changeset.change(
      state: state,
      attempted_by: node && [node, "producer-uuid"],
      attempted_at: node && DateTime.add(@now, -attempted_ago_seconds)
    )
    |> Repo.insert!()
  end

  test "a machine's heartbeat is one row per node, updated in place" do
    :ok = ObanRescue.beat("m1-git-a", DateTime.add(@now, -60))
    :ok = ObanRescue.beat("m1-git-a", @now)
    assert [{"m1-git-a", @now}] = ObanRescue.heartbeats()
  end

  test "jobs on a machine that stopped beating are released; live and just-started ones stay" do
    :ok = ObanRescue.beat("live", DateTime.add(@now, -20))
    :ok = ObanRescue.beat("gone", DateTime.add(@now, -180))

    on_live = job!("executing", "live", 600)
    on_gone = job!("executing", "gone", 600)
    never_beat = job!("executing", "old-deploy", 600)
    just_started = job!("executing", "booting", 30)
    waiting = job!("available", nil, 0)

    assert ObanRescue.release_orphans(@now) == 2

    assert Repo.reload!(on_live).state == "executing"
    assert Repo.reload!(on_gone).state == "available"
    assert Repo.reload!(never_beat).state == "available"
    assert Repo.reload!(just_started).state == "executing"
    assert Repo.reload!(waiting).state == "available"
  end

  test "heartbeats older than a day are forgotten" do
    :ok = ObanRescue.beat("ancient", DateTime.add(@now, -2, :day))
    :ok = ObanRescue.beat("live", @now)
    ObanRescue.release_orphans(@now)
    assert [{"live", _}] = ObanRescue.heartbeats()
  end
end
