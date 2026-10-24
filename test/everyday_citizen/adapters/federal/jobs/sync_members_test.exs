defmodule EverydayCitizen.Adapters.Federal.Jobs.SyncMembersTest do
  use EverydayCitizen.DataCase, async: true
  use Oban.Testing, repo: EverydayCitizen.Repo

  alias EverydayCitizen.Adapters.Federal.Jobs.{SyncCongress, SyncMembers}
  alias EverydayCitizen.Legislature.{Body, Membership, Person}
  alias EverydayCitizen.Repo

  import Ecto.Query

  @dir "test/support/fixtures/federal"

  setup do
    Req.Test.stub(EverydayCitizen.Federal, fn conn ->
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
    assert counts.people == 8
    assert counts.bodies == 3 + 4

    # Chamber terms: 12 across 8 people; committee seats: 4 (Z999999 is a synthetic orphan, skipped).
    assert counts.memberships == 12 + 4

    assert :ok = perform_job(SyncMembers, %{})
    assert counts() == counts
    assert EverydayCitizen.Provenance.last_succeeded_run("federal", "sync_members")

    seat =
      Repo.one!(
        from m in Membership,
          join: b in Body,
          on: b.id == m.body_id,
          join: s in assoc(m, :source),
          where: b.external_id == "hsag00" and m.role == "chair",
          select: s.url
      )

    assert seat =~ "committee-membership-current.json"
  end

  defp counts do
    %{
      people: Repo.aggregate(Person, :count),
      bodies: Repo.aggregate(Body, :count),
      memberships: Repo.aggregate(Membership, :count)
    }
  end
end
