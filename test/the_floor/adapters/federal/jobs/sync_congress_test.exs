defmodule TheFloor.Adapters.Federal.Jobs.SyncCongressTest do
  use TheFloor.DataCase, async: true
  use Oban.Testing, repo: TheFloor.Repo

  alias TheFloor.Adapters.Federal.Jobs.SyncCongress
  alias TheFloor.Legislature.{Body, Session}
  alias TheFloor.Repo

  @fixture "test/support/fixtures/federal/congress_gov/congress_119.json"

  test "writes bootstrap records idempotently inside a run" do
    Req.Test.stub(TheFloor.Federal, fn conn ->
      Plug.Conn.send_resp(conn, 200, File.read!(@fixture))
    end)

    assert :ok = perform_job(SyncCongress, %{"congress" => 119})
    assert :ok = perform_job(SyncCongress, %{"congress" => 119})

    assert Repo.aggregate(Body, :count) == 3
    assert Repo.aggregate(Session, :count) == 3
    assert TheFloor.Provenance.last_succeeded_run("federal", "sync_congress")
  end
end
