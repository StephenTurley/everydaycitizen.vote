defmodule TheFloor.Adapters.Federal.CoverageTest do
  use TheFloor.DataCase, async: true
  use Oban.Testing, repo: TheFloor.Repo

  alias TheFloor.Adapters.Federal.Coverage, as: FederalCoverage
  alias TheFloor.Adapters.Federal.Jobs.Coverage, as: CoverageJob
  alias TheFloor.Ingest
  alias TheFloor.Ingest.Coverage
  alias TheFloor.Ingest.Records

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
             "members:house",
             "members:senate"
           ]
  end

  test "the job records one row per check; current members exclude one who left" do
    stub_sources()

    assert :ok = perform_job(CoverageJob, %{})

    rows = Coverage.latest() |> Map.new(&{&1.name, &1})
    assert map_size(rows) == 7
    assert %{expected: 1, actual: 1, passed: true} = rows["members:house"]
    assert %{expected: 1, actual: 1, passed: true} = rows["members:senate"]
    assert %{expected: 0, actual: 0, passed: true} = rows["bills:119"]
    assert %{expected: 2, actual: 0, passed: false} = rows["votes:house:119-1"]
    assert %{expected: 3, actual: 0, passed: false} = rows["votes:senate:119-2"]
    assert TheFloor.Provenance.last_succeeded_run("federal", "coverage")
  end

  test "a failed expected-count fetch records a failed check and does not crash the job" do
    Req.Test.stub(TheFloor.Federal, fn conn ->
      if conn.host == "www.senate.gov" do
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

  defp stub_sources, do: Req.Test.stub(TheFloor.Federal, &respond/1)

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

      "/legislative/LIS/roll_call_lists/vote_menu_119_" <> rest ->
        n = if rest == "2.xml", do: 3, else: 0
        Plug.Conn.send_resp(conn, 200, menu_xml(n))
    end
  end

  defp term(chamber, year), do: %{"chamber" => chamber, "startYear" => year}

  defp menu_xml(n) do
    votes = for i <- 1..n//1, into: "", do: "<vote><vote_number>#{i}</vote_number></vote>"
    "<vote_summary><votes>#{votes}</votes></vote_summary>"
  end

  defp src, do: Records.SourceRef.new("https://example.test/x", "x")

  defp write!(record) do
    {:ok, _} = Ingest.write(record, nil)
    :ok
  end
end
