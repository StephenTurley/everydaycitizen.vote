defmodule EverydayCitizen.LegislatureChangeoverDayTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Legislature

  @src Records.SourceRef.new("https://x.test/changeover", "c")

  setup do
    EverydayCitizen.FloorFixtures.iowa!()
    :ok
  end

  defp member!(id, body, district, start_date, end_date) do
    {:ok, _} =
      Ingest.write(%Records.Person{identifiers: [{"bioguide", id}], name: id, source: @src}, nil)

    {:ok, _} =
      Ingest.write(
        %Records.Membership{
          jurisdiction: "federal",
          person: {"bioguide", id},
          body_external_id: body,
          role: "member",
          district: district,
          start_date: start_date,
          end_date: end_date,
          source: @src
        },
        nil
      )
  end

  defp names(rows), do: rows |> Enum.map(& &1.person.name) |> Enum.sort()

  defp both(seats_exact, seats_matching, on) do
    {names(Legislature.current_members("federal", seats_exact, on)),
     names(Legislature.current_members_matching("federal", seats_matching, on))}
  end

  test "on the day a seat changes hands only the incoming member is current" do
    member!("A", "house", "OH-3", ~D[2025-01-03], ~D[2027-01-03])
    member!("B", "house", "OH-3", ~D[2027-01-03], ~D[2029-01-03])

    exact = [{"house", "OH-3"}]
    matching = [{"house", {:exact, "OH-3"}}]
    assert both(exact, matching, ~D[2027-01-03]) == {["B"], ["B"]}
    assert both(exact, matching, ~D[2027-01-02]) == {["A"], ["A"]}
  end

  test "a senator continuing in office stays beside the incoming one" do
    member!("A", "senate", "OH", ~D[2021-01-03], ~D[2027-01-03])
    member!("B", "senate", "OH", ~D[2027-01-03], ~D[2033-01-03])
    member!("C", "senate", "OH", ~D[2023-01-03], ~D[2029-01-03])

    assert both([{"senate", "OH"}], [{"senate", {:exact, "OH"}}], ~D[2027-01-03]) ==
             {["B", "C"], ["B", "C"]}
  end

  test "a member whose term ends with no successor yet is still listed on the last day" do
    member!("A", "house", "OH-3", ~D[2025-01-03], ~D[2026-11-04])

    assert both([{"house", "OH-3"}], [{"house", {:exact, "OH-3"}}], ~D[2026-11-04]) ==
             {["A"], ["A"]}
  end
end
