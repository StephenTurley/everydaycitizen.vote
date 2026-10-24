defmodule EverydayCitizen.Adapters.Federal.Jobs.SyncCongressTest do
  use EverydayCitizen.DataCase, async: true
  use Oban.Testing, repo: EverydayCitizen.Repo

  alias EverydayCitizen.Adapters.Federal.Jobs.SyncCongress
  alias EverydayCitizen.Legislature.{Body, Session}
  alias EverydayCitizen.Repo

  @fixture "test/support/fixtures/federal/congress_gov/congress_119.json"

  test "writes bootstrap records idempotently inside a run" do
    Req.Test.stub(EverydayCitizen.Federal, fn conn ->
      Plug.Conn.send_resp(conn, 200, File.read!(@fixture))
    end)

    assert :ok = perform_job(SyncCongress, %{"congress" => 119})
    assert :ok = perform_job(SyncCongress, %{"congress" => 119})

    assert Repo.aggregate(Body, :count) == 3
    assert Repo.aggregate(Session, :count) == 3
    assert EverydayCitizen.Provenance.last_succeeded_run("federal", "sync_congress")
  end
end
