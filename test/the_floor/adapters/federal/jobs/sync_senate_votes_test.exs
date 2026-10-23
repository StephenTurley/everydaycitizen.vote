defmodule TheFloor.Adapters.Federal.Jobs.SyncSenateVotesTest do
  use TheFloor.DataCase, async: true
  use Oban.Testing, repo: TheFloor.Repo

  import Ecto.Query

  alias TheFloor.Adapters.Federal.Jobs.SyncSenateVotes
  alias TheFloor.Ingest
  alias TheFloor.Ingest.Records
  alias TheFloor.Provenance
  alias TheFloor.Votes.Vote

  @dir "test/support/fixtures/federal/voteview"
  @votes_url "https://voteview.com/static/data/out/votes/S119_votes.csv"

  setup do
    write!(%Records.Jurisdiction{
      key: "federal",
      name: "Federal",
      classification: "federal",
      source: src()
    })

    write!(%Records.LegislativeSession{jurisdiction: "federal", identifier: "119", source: src()})

    write!(%Records.LegislativeSession{
      jurisdiction: "federal",
      identifier: "119-1",
      parent_identifier: "119",
      source: src()
    })

    write!(%Records.LegislativeSession{
      jurisdiction: "federal",
      identifier: "119-2",
      parent_identifier: "119",
      source: src()
    })

    write!(%Records.Body{
      jurisdiction: "federal",
      external_id: "senate",
      name: "Senate",
      classification: "chamber",
      source: src()
    })

    write!(%Records.Person{
      identifiers: [{"lis", "S153"}, {"bioguide", "G000386"}],
      name: "Chuck Grassley",
      source: src()
    })

    write!(%Records.Bill{
      jurisdiction: "federal",
      session_identifier: "119",
      external_id: "119-s-5",
      identifier: "S. 5",
      classification: "bill",
      title: "Example",
      source: src()
    })

    :ok
  end

  # Serves the three Voteview files and reports each request to the test.
  defp stub do
    Req.Test.stub(TheFloor.Federal, fn conn ->
      send(self(), {:request, conn.host, conn.request_path})

      case Regex.run(
             ~r{^/static/data/out/(rollcalls|votes|members)/S119_\1\.csv$},
             conn.request_path
           ) do
        [_, kind] -> Plug.Conn.send_resp(conn, 200, File.read!("#{@dir}/S119_#{kind}.csv"))
        _ -> Plug.Conn.send_resp(conn, 404, "nope")
      end
    end)
  end

  defp requests(acc \\ []) do
    receive do
      {:request, host, path} -> requests([{host, path} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "stores every session's votes with bill and senator links, from three files" do
    stub()
    assert :ok = perform_job(SyncSenateVotes, %{})

    assert requests() == [
             {"voteview.com", "/static/data/out/rollcalls/S119_rollcalls.csv"},
             {"voteview.com", "/static/data/out/votes/S119_votes.csv"},
             {"voteview.com", "/static/data/out/members/S119_members.csv"}
           ]

    assert Repo.all(from v in Vote, select: v.external_id, order_by: v.external_id) ==
             ["senate-119-1-1", "senate-119-1-2", "senate-119-2-1"]

    vote =
      Vote
      |> Repo.get_by!(external_id: "senate-119-1-1")
      |> Repo.preload([:bill, :source, :positions])

    assert vote.bill.external_id == "119-s-5"
    assert vote.source.url == @votes_url
    assert {vote.yea_count, vote.nay_count, vote.absent_count} == {84, 9, 6}
    assert Enum.count(vote.positions, & &1.person_id) == 1

    assert Provenance.last_succeeded_run("federal", "sync_senate_votes")
  end

  test "with a session arg only that session's votes are written" do
    stub()
    assert :ok = perform_job(SyncSenateVotes, %{"session" => 2})
    assert Repo.all(from v in Vote, select: v.external_id) == ["senate-119-2-1"]
  end

  test "re-running is idempotent" do
    stub()
    assert :ok = perform_job(SyncSenateVotes, %{})
    assert :ok = perform_job(SyncSenateVotes, %{})
    assert Repo.aggregate(Vote, :count) == 3
  end

  test "a failed download fails the run" do
    Req.Test.stub(TheFloor.Federal, fn conn -> Plug.Conn.send_resp(conn, 503, "busy") end)
    assert {:error, _} = perform_job(SyncSenateVotes, %{})
    refute Provenance.last_succeeded_run("federal", "sync_senate_votes")
  end

  defp src, do: Records.SourceRef.new("https://example.test/x", "x")

  defp write!(record) do
    {:ok, row} = Ingest.write(record, nil)
    row
  end
end
