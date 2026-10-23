defmodule TheFloor.Adapters.Federal.Jobs.SyncMembersTest do
  use TheFloor.DataCase, async: true
  use Oban.Testing, repo: TheFloor.Repo

  alias TheFloor.Adapters.Federal.Jobs.{SyncCongress, SyncMembers}
  alias TheFloor.Legislature.{Body, Membership, Person}
  alias TheFloor.Repo

  @dir "test/support/fixtures/federal"

  setup do
    Req.Test.stub(TheFloor.Federal, fn conn ->
      body =
        case conn.request_path do
          "/v3/congress/119" -> File.read!("#{@dir}/congress_gov/congress_119.json")
          "/congress-legislators/" <> file -> File.read!("#{@dir}/legislators/#{file}")
        end

      Plug.Conn.send_resp(conn, 200, body)
    end)

    assert :ok = perform_job(SyncCongress, %{"congress" => 119})
  end

  @tag :capture_log
  test "writes people, memberships and committees idempotently" do
    assert :ok = perform_job(SyncMembers, %{})
    counts = counts()
    assert counts.people == 4
    assert counts.bodies == 3 + 4

    # Chamber terms: Cantwell 2, Bennet 1, Begich 1, Brown 1; committee seats: 4 (Z999999 is unknown and skipped).
    assert counts.memberships == 5 + 4

    assert :ok = perform_job(SyncMembers, %{})
    assert counts() == counts
    assert TheFloor.Provenance.last_succeeded_run("federal", "sync_members")
  end

  defp counts do
    %{
      people: Repo.aggregate(Person, :count),
      bodies: Repo.aggregate(Body, :count),
      memberships: Repo.aggregate(Membership, :count)
    }
  end
end
