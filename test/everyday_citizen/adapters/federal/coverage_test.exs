defmodule EverydayCitizen.Adapters.Federal.CoverageTest do
  use EverydayCitizen.DataCase, async: true
  use Oban.Testing, repo: EverydayCitizen.Repo

  import Ecto.Query

  alias EverydayCitizen.Adapters.Federal.Coverage, as: FederalCoverage
  alias EverydayCitizen.Adapters.Federal.Jobs.Coverage, as: CoverageJob
  alias EverydayCitizen.Adapters.Federal.Jobs.SyncBills
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Coverage
  alias EverydayCitizen.Ingest.Records

  setup do
    write!(%Records.Jurisdiction{
      key: "federal",
      name: "Federal",
      classification: "federal",
      time_zone: "America/New_York",
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

    for id <- ["house", "senate"] do
      write!(%Records.Body{
        jurisdiction: "federal",
        external_id: id,
        name: id,
        classification: "chamber",
        source: src()
      })
    end

    for {id, body, end_date} <- [
          {"A000001", "house", nil},
          {"A000002", "house", ~D[2020-01-01]},
          {"S000001", "senate", nil}
        ] do
      write!(%Records.Person{identifiers: [{"bioguide", id}], name: id, source: src()})

      write!(%Records.Membership{
        jurisdiction: "federal",
        person: {"bioguide", id},
        body_external_id: body,
        role: "member",
        start_date: ~D[2019-01-03],
        end_date: end_date,
        source: src()
      })
    end

    :ok
  end

  test "checks cover bills, each stored session's votes for both chambers, and members" do
    names = 119 |> FederalCoverage.checks() |> Enum.map(&elem(&1, 0))

    assert names == [
             "bills:119",
             "votes:house:119-1",
             "votes:house:119-2",
             "votes:senate:119-1",
             "votes:senate:119-2",
             "votes:senate:tallies",
             "members:house",
             "members:senate"
           ]
  end

  test "with no stored child sessions each chamber gets one failed vote check" do
    EverydayCitizen.Repo.delete_all(
      from s in EverydayCitizen.Legislature.Session, where: not is_nil(s.parent_id)
    )

    stub_sources()
    assert :ok = perform_job(CoverageJob, %{})

    rows = Coverage.latest() |> Map.new(&{&1.name, &1})

    for name <- ["votes:house", "votes:senate"] do
      assert %{passed: false, error: error} = rows[name]
      assert error =~ "no child sessions stored"
    end
  end

  test "the job snoozes while other ingest jobs are still to run" do
    {:ok, _} = Oban.insert(SyncBills.new(%{}))
    assert {:snooze, 300} = perform_job(CoverageJob, %{})
    assert Coverage.latest() == []
  end

  test "the job records one row per check; current members exclude one who left" do
    stub_sources()

    assert :ok = perform_job(CoverageJob, %{})

    rows = Coverage.latest() |> Map.new(&{&1.name, &1})
    assert map_size(rows) == 8
    assert %{expected: 1, actual: 1, passed: true} = rows["members:house"]
    assert %{expected: 1, actual: 1, passed: true} = rows["members:senate"]
    assert %{expected: 0, actual: 0, passed: true} = rows["bills:119"]
    assert %{expected: 2, actual: 0, passed: false} = rows["votes:house:119-1"]
    # The Voteview fixture lists two session-1 roll calls and one in session 2.
    assert %{expected: 1, actual: 0, passed: false} = rows["votes:senate:119-2"]
    assert EverydayCitizen.Provenance.last_succeeded_run("federal", "coverage")
  end

  test "a failed expected-count fetch records a failed check and does not crash the job" do
    Req.Test.stub(EverydayCitizen.Federal, fn conn ->
      if conn.host == "voteview.com" do
        Plug.Conn.send_resp(conn, 403, "denied")
      else
        respond(conn)
      end
    end)

    assert :ok = perform_job(CoverageJob, %{})

    rows = Coverage.latest() |> Map.new(&{&1.name, &1})
    assert %{expected: nil, passed: false, error: error} = rows["votes:senate:119-1"]
    assert error =~ "403"
    assert rows["members:house"].passed
  end

  describe "votes:senate:tallies" do
    setup do
      for {s, start} <- [{1, ~D[2025-01-03]}, {2, ~D[2026-01-03]}] do
        write!(%Records.LegislativeSession{
          jurisdiction: "federal",
          identifier: "119-#{s}",
          parent_identifier: "119",
          start_date: start,
          source: src()
        })
      end

      write!(%Records.Bill{
        jurisdiction: "federal",
        session_identifier: "119",
        external_id: "119-s-5",
        identifier: "S. 5",
        classification: "bill",
        title: "Example",
        source: src()
      })

      actions = [
        {~D[2025-01-09],
         "Cloture invoked in Senate by Yea-Nay Vote. 84 - 9. Record Vote Number: 1."},
        # The same roll call recorded again by another system counts once.
        {~D[2025-01-09],
         "Motion to invoke cloture agreed to by Yea-Nay Vote. 84 - 9. Record Vote Number: 1."},
        {~D[2025-01-13],
         "Motion to proceed agreed to by Yea-Nay Vote. 50 - 40. Record Vote Number: 2."},
        {~D[2026-01-05], "Passed Senate by Yea-Nay Vote. 50 - 35. Record Vote Number: 1."},
        {~D[2025-01-20], "Passed Senate without amendment by Voice Vote."}
      ]

      write!(%Records.BillActions{
        jurisdiction: "federal",
        bill_external_id: "119-s-5",
        actions:
          for {{date, text}, i} <- Enum.with_index(actions) do
            %Records.BillAction{position: i, date: date, description: text}
          end,
        source: src()
      })

      for {id, session, yea, nay} <- [
            {1, "119-1", 84, 9},
            {2, "119-1", 82, 10},
            {1, "119-2", 50, 35}
          ] do
        write!(%Records.Vote{
          jurisdiction: "federal",
          body_external_id: "senate",
          session_identifier: session,
          external_id: "senate-#{session}-#{id}",
          voted_on: ~D[2025-01-09],
          voted_at: ~U[2025-01-09 05:00:00Z],
          counts: %{yea: yea, nay: nay, present: 0, absent: 0},
          positions: [],
          source: src()
        })
      end

      :ok
    end

    test "stored Senate totals must match the tallies printed in bill actions" do
      {_, expected, actual, _tolerance} =
        119 |> FederalCoverage.checks() |> List.keyfind("votes:senate:tallies", 0)

      # Rolls 119-1-1 and 119-2-1 match; 119-1-2 is stored as 82-10, recorded as 50-40.
      assert expected.() == {:ok, 3}
      assert actual.() == 2
    end
  end

  defp stub_sources, do: Req.Test.stub(EverydayCitizen.Federal, &respond/1)

  defp respond(conn) do
    case conn.request_path do
      "/v3/bill/119" ->
        Req.Test.json(conn, %{"bills" => [], "pagination" => %{"count" => 0}})

      "/v3/house-vote/119/1" ->
        Req.Test.json(conn, %{"pagination" => %{"count" => 2}})

      "/v3/house-vote/119/2" ->
        Req.Test.json(conn, %{"pagination" => %{"count" => 0}})

      "/v3/member/congress/119" ->
        Req.Test.json(conn, %{
          "members" => [
            # Latest term decides the chamber, whatever the order of the terms.
            %{
              "terms" => %{
                "item" => [term("House of Representatives", 2019), term("Senate", 2023)]
              }
            },
            %{
              "terms" => %{
                "item" => [term("House of Representatives", 2021), term("Senate", 2015)]
              }
            }
          ],
          "pagination" => %{"count" => 2}
        })

      "/static/data/out/rollcalls/S119_rollcalls.csv" ->
        csv = File.read!("test/support/fixtures/federal/voteview/S119_rollcalls.csv")
        Plug.Conn.send_resp(conn, 200, csv)
    end
  end

  defp term(chamber, year), do: %{"chamber" => chamber, "startYear" => year}

  defp src, do: Records.SourceRef.new("https://example.test/x", "x")

  defp write!(record) do
    {:ok, _} = Ingest.write(record, nil)
    :ok
  end
end
