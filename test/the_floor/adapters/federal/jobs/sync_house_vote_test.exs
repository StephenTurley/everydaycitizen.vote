defmodule TheFloor.Adapters.Federal.Jobs.SyncHouseVoteTest do
  use TheFloor.DataCase, async: true
  use Oban.Testing, repo: TheFloor.Repo

  alias TheFloor.Adapters.Federal.Jobs.{SyncHouseVote, SyncHouseVotes}
  alias TheFloor.Ingest
  alias TheFloor.Ingest.Records
  alias TheFloor.Repo
  alias TheFloor.Votes.{Vote, VotePosition}

  @dir "test/support/fixtures/federal/congress_gov"
  @args %{"congress" => 119, "session" => 1, "roll" => 17}

  setup do
    write!(%Records.Jurisdiction{
      key: "federal",
      name: "Federal",
      classification: "federal",
      source: src()
    })

    write!(%Records.LegislativeSession{jurisdiction: "federal", identifier: "119", source: src()})

    for s <- 1..2 do
      write!(%Records.LegislativeSession{
        jurisdiction: "federal",
        identifier: "119-#{s}",
        parent_identifier: "119",
        source: src()
      })
    end

    write!(%Records.Body{
      jurisdiction: "federal",
      external_id: "house",
      name: "House",
      classification: "chamber",
      source: src()
    })

    write!(%Records.Person{
      identifiers: [{"bioguide", "A000055"}],
      name: "Robert Aderholt",
      source: src()
    })

    write!(%Records.Bill{
      jurisdiction: "federal",
      session_identifier: "119",
      external_id: "119-hr-30",
      identifier: "H.R. 30",
      classification: "bill",
      title: "Example",
      source: src()
    })

    :ok
  end

  test "stores the vote with bill and positions, idempotently" do
    stub_vote(17)
    assert :ok = perform_job(SyncHouseVote, @args)

    vote = Repo.one!(Vote) |> Repo.preload([:bill, :positions])
    assert vote.external_id == "house-119-1-17"
    assert vote.bill.external_id == "119-hr-30"
    assert {vote.yea_count, vote.nay_count, vote.absent_count} == {274, 145, 15}
    assert length(vote.positions) == 6
    assert Enum.count(vote.positions, & &1.person_id) == 1

    assert :ok = perform_job(SyncHouseVote, @args)
    assert Repo.aggregate(Vote, :count) == 1
    assert Repo.aggregate(VotePosition, :count) == 6
  end

  test "a vote without legislation is stored without a bill" do
    stub_vote(2)
    assert :ok = perform_job(SyncHouseVote, Map.put(@args, "roll", 2))
    assert Repo.one!(Vote).bill_id == nil
  end

  test "list job enqueues unstored rolls plus rolls updated since the cursor" do
    stub_vote(17)
    assert :ok = perform_job(SyncHouseVote, @args)

    # Previous run started after roll 17's update (2025-06-24).
    {:ok, run} = TheFloor.Provenance.start_run("federal", "sync_house_votes")
    {:ok, _} = TheFloor.Provenance.finish_run(run, :succeeded, %{}, nil)
    set_run_started!(run, ~U[2025-10-01 00:00:00.000000Z])
    stub_list()

    assert :ok = perform_job(SyncHouseVotes, %{"congress" => 119, "session" => 1})

    # 17 is stored and older than the cursor, so only it is skipped.
    assert rolls() == [2, 240, 259, 306]
  end

  test "a stored roll updated since the cursor is re-enqueued" do
    stub_vote(17)
    assert :ok = perform_job(SyncHouseVote, @args)
    {:ok, run} = TheFloor.Provenance.start_run("federal", "sync_house_votes")
    {:ok, _} = TheFloor.Provenance.finish_run(run, :succeeded, %{}, nil)
    set_run_started!(run, ~U[2025-01-01 00:00:00.000000Z])
    stub_list()

    assert :ok = perform_job(SyncHouseVotes, %{"congress" => 119, "session" => 1})
    assert 17 in rolls()
  end

  test "without a session arg every stored session of the congress is synced" do
    Req.Test.stub(TheFloor.Federal, fn conn ->
      assert conn.request_path =~ ~r{/house-vote/119/[12]$}
      n = if conn.request_path =~ "/119/1", do: 1, else: 2

      items =
        for r <- 1..n do
          %{"rollCallNumber" => r, "updateDate" => "2025-01-01T00:00:00-05:00"}
        end

      Req.Test.json(conn, %{"houseRollCallVotes" => items, "pagination" => %{"count" => n}})
    end)

    assert :ok = perform_job(SyncHouseVotes, %{})

    pairs =
      for %{args: %{"session" => s, "roll" => r}} <- all_enqueued(worker: SyncHouseVote),
          do: {s, r}

    assert Enum.sort(pairs) == [{1, 1}, {2, 1}, {2, 2}]
  end

  defp rolls do
    Enum.sort(for %{args: %{"roll" => roll}} <- all_enqueued(worker: SyncHouseVote), do: roll)
  end

  defp set_run_started!(run, at) do
    run |> Ecto.Changeset.change(started_at: at) |> Repo.update!()
  end

  defp stub_list do
    body = @dir |> Path.join("house_vote_list.json") |> File.read!()

    Req.Test.stub(TheFloor.Federal, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, body)
    end)
  end

  defp stub_vote(roll) do
    name = "house_vote_119_1_#{roll}"

    Req.Test.stub(TheFloor.Federal, fn conn ->
      file = if conn.request_path =~ "members", do: "#{name}_members.json", else: "#{name}.json"
      body = @dir |> Path.join(file) |> File.read!()

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, body)
    end)
  end

  defp src, do: Records.SourceRef.new("https://example.test/x", "x")

  defp write!(record) do
    {:ok, _} = Ingest.write(record, nil)
    :ok
  end
end
