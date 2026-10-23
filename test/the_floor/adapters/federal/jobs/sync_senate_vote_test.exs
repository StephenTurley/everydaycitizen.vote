defmodule TheFloor.Adapters.Federal.Jobs.SyncSenateVoteTest do
  use TheFloor.DataCase, async: true
  use Oban.Testing, repo: TheFloor.Repo

  alias TheFloor.Adapters.Federal.Jobs.{SyncSenateVote, SyncSenateVotes}
  alias TheFloor.Ingest
  alias TheFloor.Ingest.Records
  alias TheFloor.Repo
  alias TheFloor.Votes.{Vote, VotePosition}

  @dir "test/support/fixtures/federal/senate"
  @args %{"congress" => 119, "session" => 1, "roll" => 1}

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

    write!(%Records.Body{
      jurisdiction: "federal",
      external_id: "senate",
      name: "Senate",
      classification: "chamber",
      source: src()
    })

    write!(%Records.Person{
      identifiers: [{"lis", "S428"}, {"bioguide", "A000382"}],
      name: "Angela Alsobrooks",
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

  test "stores the vote with its bill and positions, idempotently" do
    stub_vote("vote_119_1_00001.xml")
    assert :ok = perform_job(SyncSenateVote, @args)

    vote = Repo.one!(Vote) |> Repo.preload([:bill, :positions])
    assert vote.external_id == "senate-119-1-1"
    assert vote.bill.external_id == "119-s-5"
    assert {vote.yea_count, vote.nay_count, vote.absent_count} == {84, 9, 7}
    assert length(vote.positions) == 4
    assert Enum.count(vote.positions, & &1.person_id) == 1

    assert :ok = perform_job(SyncSenateVote, @args)
    assert Repo.aggregate(Vote, :count) == 1
    assert Repo.aggregate(VotePosition, :count) == 4
  end

  test "a nomination vote is stored without a bill" do
    stub_vote("vote_119_1_nomination.xml")
    assert :ok = perform_job(SyncSenateVote, Map.put(@args, "roll", 5))
    assert Repo.one!(Vote).bill_id == nil
  end

  test "requests the zero-padded vote url" do
    assert SyncSenateVote.url(119, 1, 7) ==
             "https://www.senate.gov/legislative/LIS/roll_call_votes/vote1191/vote_119_1_00007.xml"
  end

  test "list job enqueues rolls not stored plus the 10 most recent" do
    stub_vote("vote_119_1_00001.xml")
    assert :ok = perform_job(SyncSenateVote, @args)
    stub_vote("vote_119_1_nomination.xml")
    assert :ok = perform_job(SyncSenateVote, Map.put(@args, "roll", 5))
    # Stored rolls are 1 and 5; the menu lists rolls 1..15.
    stub_menu(15)

    assert :ok = perform_job(SyncSenateVotes, %{"congress" => 119, "session" => 1})

    rolls =
      for %{args: %{"roll" => roll}} <- all_enqueued(worker: SyncSenateVote), do: roll

    # 1 and 5 are stored and not recent, so only they are skipped.
    assert Enum.sort(rolls) == Enum.to_list(2..15) -- [5]
    assert TheFloor.Provenance.last_succeeded_run("federal", "sync_senate_votes")
  end

  defp stub_vote(file) do
    Req.Test.stub(TheFloor.Federal, fn conn ->
      Plug.Conn.send_resp(conn, 200, File.read!(Path.join(@dir, file)))
    end)
  end

  defp stub_menu(count) do
    votes =
      for n <- count..1//-1 do
        "<vote><vote_number>#{String.pad_leading("#{n}", 5, "0")}</vote_number></vote>"
      end

    xml = "<vote_summary><votes>#{Enum.join(votes)}</votes></vote_summary>"
    Req.Test.stub(TheFloor.Federal, fn conn -> Plug.Conn.send_resp(conn, 200, xml) end)
  end

  defp src, do: Records.SourceRef.new("https://example.test/x", "x")

  defp write!(record) do
    {:ok, _} = Ingest.write(record, nil)
    :ok
  end
end
