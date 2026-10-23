defmodule TheFloor.Adapters.Federal.FullIngestTest do
  @moduledoc """
  First full ingest on an empty database, through the same enqueue path as
  `mix the_floor.ingest`, with every source stubbed by one consistent fixture set.

  On a real first run the list jobs start together (`ingest` concurrency 4), so
  they may finish in any order. The ingest must reach the same complete state
  whatever order they run in; the reverse-order case is the adversarial one
  (votes, bills and meetings run before the congress and members exist).
  """
  use TheFloor.DataCase, async: true
  use Oban.Testing, repo: TheFloor.Repo

  import Ecto.Query

  alias TheFloor.Adapters.Federal.Jobs
  alias TheFloor.Calendar.Event
  alias TheFloor.Ingest.CoverageCheck
  alias TheFloor.Legislation.{Bill, Sponsorship}
  alias TheFloor.Repo
  alias TheFloor.Votes.Vote

  @moduletag :capture_log

  @fixtures "test/support/fixtures/federal"
  # Each drain pass re-stages snoozed and retryable jobs; a healthy ingest settles in
  # a handful of passes, so hitting the cap means jobs keep snoozing or failing.
  @max_passes 40

  @house_people ~w(R000614 G000597 M000317 F000475 C001116 H001077
                   A000055 A000148 A000369 A000370 B001281 D000600)
  # Senators who cast votes in roll call 1 of the Voteview fixture.
  @senators ~w(G000386 M000133 S000148 W000779)

  setup do
    Req.Test.stub(TheFloor.Federal, &respond/1)
    :ok
  end

  test "registry order: a first full ingest links every reference" do
    TheFloor.Ingest.Jobs.enqueue(Jobs.all())
    drain!()
    assert_complete()
  end

  test "reverse order: list jobs finishing before their prerequisites still converge" do
    TheFloor.Ingest.Jobs.enqueue(Enum.reverse(Jobs.all()))
    drain!()
    assert_complete()
  end

  defp assert_complete do
    bill = Repo.get_by!(Bill, external_id: "119-hr-22")

    sponsorships = Repo.all(from s in Sponsorship, where: s.bill_id == ^bill.id)
    assert length(sponsorships) == 6
    assert Enum.all?(sponsorships, & &1.person_id)

    house_vote = Repo.get_by!(Vote, external_id: "house-119-1-17") |> Repo.preload(:positions)
    assert house_vote.bill_id == bill.id
    assert length(house_vote.positions) == 6
    assert Enum.all?(house_vote.positions, & &1.person_id)

    senate_vote = Repo.get_by!(Vote, external_id: "senate-119-1-1") |> Repo.preload(:positions)
    linked = senate_vote.positions |> Enum.filter(& &1.person_id) |> length()
    assert linked == length(@senators)

    meeting = Repo.get_by!(Event, external_id: "meeting-118405")
    assert meeting.body_id

    names = Repo.all(from c in CoverageCheck, select: c.name)
    assert "votes:house:119-1" in names
    assert "votes:senate:119-1" in names
    assert "votes:senate:tallies" in names
    assert "bills:119" in names
  end

  # Drains both queues until nothing is left to run (snoozed jobs included).
  defp drain!(pass \\ 1)

  defp drain!(pass) when pass > @max_passes do
    flunk("ingest did not settle after #{@max_passes} drain passes: #{inspect(pending())}")
  end

  defp drain!(pass) do
    ingest = Oban.drain_queue(queue: :ingest, with_scheduled: true)
    text = Oban.drain_queue(queue: :text, with_scheduled: true)

    if Enum.all?([ingest, text], &(Map.values(&1) |> Enum.sum() == 0)),
      do: :ok,
      else: drain!(pass + 1)
  end

  defp pending do
    Repo.all(
      from j in Oban.Job,
        where: j.state in ["available", "scheduled", "retryable", "executing"],
        select: {j.worker, j.state, j.meta}
    )
  end

  # --- stubbed sources -------------------------------------------------------

  defp respond(%Plug.Conn{host: "api.congress.gov", request_path: "/v3" <> path} = conn),
    do: congress_gov(conn, path)

  defp respond(%Plug.Conn{host: "unitedstates.github.io", request_path: path} = conn),
    do: json(conn, legislators(Path.basename(path, ".json")))

  # The first bill sync reads the BILLSTATUS bulk zip; the BILLS text zips are
  # missing, so text falls back to the per-version file.
  defp respond(%Plug.Conn{host: "www.govinfo.gov", request_path: path} = conn) do
    cond do
      path == "/bulkdata/BILLSTATUS/119/hr/BILLSTATUS-119-hr.zip" ->
        reply(conn, 200, billstatus_zip())

      path =~ "BILLS-119hr22ih.xml" ->
        reply(conn, 200, read("govinfo/BILLS-119hr22ih.xml"))

      true ->
        reply(conn, 404, "")
    end
  end

  defp respond(%Plug.Conn{host: "docs.house.gov"} = conn),
    do: reply(conn, 200, "<!DOCTYPE html><html><body>No schedule</body></html>")

  defp respond(%Plug.Conn{host: "voteview.com", request_path: path} = conn) do
    case Regex.run(~r{/(rollcalls|votes|members)/S119_\1\.csv$}, path) do
      [_, kind] -> reply(conn, 200, read("voteview/S119_#{kind}.csv"))
      _ -> reply(conn, 404, "")
    end
  end

  defp respond(%Plug.Conn{host: "www.senate.gov", request_path: path} = conn) do
    if path =~ "floor_schedule",
      do: reply(conn, 200, read("senate/floor_schedule_SYNTHETIC.htm")),
      else: reply(conn, 404, "")
  end

  defp congress_gov(conn, "/congress/119"), do: reply(conn, 200, cg("congress_119.json"))

  defp congress_gov(conn, "/bill/119"),
    do: json(conn, %{bills: [%{type: "HR", number: "22"}], pagination: %{count: 1}})

  defp congress_gov(conn, "/bill/119/hr/22" <> rest) do
    file = if rest == "", do: "bill.json", else: String.trim_leading(rest, "/") <> ".json"
    reply(conn, 200, cg("bill_119_hr_22/" <> file))
  end

  defp congress_gov(conn, "/house-vote/119/1"),
    do:
      json(conn, %{
        houseRollCallVotes: [%{rollCallNumber: 17, updateDate: "2025-06-24T08:43:33-04:00"}],
        pagination: %{count: 1}
      })

  defp congress_gov(conn, "/house-vote/119/2"),
    do: json(conn, %{houseRollCallVotes: [], pagination: %{count: 0}})

  # Roll 17 is on H.R. 30 in the capture; point it at the bill this set ingests.
  defp congress_gov(conn, "/house-vote/119/1/17" <> rest) do
    file =
      if rest == "/members",
        do: "house_vote_119_1_17_members.json",
        else: "house_vote_119_1_17.json"

    reply(
      conn,
      200,
      file |> cg() |> String.replace(~s("legislationNumber": "30"), ~s("legislationNumber": "22"))
    )
  end

  defp congress_gov(conn, "/committee-meeting/119/house"),
    do:
      json(conn, %{
        committeeMeetings: [%{chamber: "House", congress: 119, eventId: "118405"}],
        pagination: %{count: 1}
      })

  defp congress_gov(conn, "/committee-meeting/119/senate"),
    do: json(conn, %{committeeMeetings: [], pagination: %{count: 0}})

  # The captured meeting's committee is not in the committee fixture; use one that is.
  defp congress_gov(conn, "/committee-meeting/119/house/118405"),
    do:
      reply(
        conn,
        200,
        "committee_meeting_house_118405.json" |> cg() |> String.replace("hsed13", "hsag03")
      )

  defp congress_gov(conn, "/member/congress/119"),
    do: json(conn, %{members: [], pagination: %{count: 0}})

  defp congress_gov(conn, path),
    do: flunk("unexpected Congress.gov request #{path} #{inspect(conn.query_string)}")

  defp legislators("legislators-current") do
    reps =
      for id <- @house_people do
        legislator(%{bioguide: id}, "rep", district: 1)
      end

    senators =
      for id <- @senators do
        legislator(%{bioguide: id}, "sen", [])
      end

    reps ++ senators
  end

  defp legislators("legislators-historical"), do: []

  defp legislators(name),
    do: "legislators/#{name}.json" |> read() |> JSON.decode!()

  defp legislator(ids, type, extra) do
    term =
      Map.merge(
        %{type: type, start: "2025-01-03", end: "2027-01-03", state: "TX", party: "Republican"},
        Map.new(extra)
      )

    %{id: ids, name: %{first: "First", last: ids.bioguide}, terms: [term]}
  end

  defp cg(file), do: read("congress_gov/" <> file)
  defp read(path), do: File.read!(Path.join(@fixtures, path))

  defp json(conn, term), do: reply(conn, 200, JSON.encode!(term))

  defp reply(conn, status, body), do: Plug.Conn.send_resp(conn, status, body)

  defp billstatus_zip do
    entry = {~c"BILLSTATUS-119hr22.xml", read("govinfo/BILLSTATUS-119hr22.xml")}
    {:ok, {_, bytes}} = :zip.create(~c"BILLSTATUS-119-hr.zip", [entry], [:memory])
    bytes
  end
end
