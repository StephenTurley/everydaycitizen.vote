defmodule EverydayCitizen.CalendarWeekTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.Calendar
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records

  @src Records.SourceRef.new("https://x.test/e", "e")

  setup do
    people = EverydayCitizen.FloorFixtures.iowa!()

    {:ok, _} =
      Ingest.write(
        %Records.Body{
          jurisdiction: "federal",
          external_id: "ssju00",
          name: "Committee on the Judiciary",
          classification: "committee",
          source: @src
        },
        nil
      )

    {:ok, _} =
      Ingest.write(
        %Records.Membership{
          jurisdiction: "federal",
          person: {"bioguide", "G000386"},
          body_external_id: "ssju00",
          role: "chair",
          source: @src
        },
        nil
      )

    for {id, body, at, bills, labels} <- [
          {"floor-1", "senate", ~U[2026-10-26 14:00:00Z], ["119-s-5"], []},
          {"meet-1", "ssju00", ~U[2026-10-27 15:00:00Z], [], ["H.R. 999999"]},
          {"floor-2", "house", ~U[2026-10-28 14:00:00Z], [], []},
          {"later", "senate", ~U[2026-11-05 14:00:00Z], [], []}
        ] do
      {:ok, _} =
        Ingest.write(
          %Records.Event{
            jurisdiction: "federal",
            body_external_id: body,
            external_id: id,
            classification: if(body == "ssju00", do: "hearing", else: "floor"),
            title: "Event #{id}",
            start_at: at,
            bill_external_ids: bills,
            raw_bill_labels: labels,
            source: @src
          },
          nil
        )
    end

    people
  end

  defp ids(days), do: for(%{events: events} <- days, e <- events, do: e.external_id)

  test "seven days from the given date, grouped by day, the rest excluded" do
    days = Calendar.week("federal", ~D[2026-10-26], [])
    assert ids(days) == ["floor-1", "meet-1", "floor-2"]
    assert Enum.map(days, & &1.date) == [~D[2026-10-26], ~D[2026-10-27], ~D[2026-10-28]]

    assert [%{body: %{name: "Senate"}, event_bills: [%{bill: %{external_id: "119-s-5"}}]} | _] =
             hd(days).events
  end

  test "for some people: their committees' meetings and items on bills they sponsor or cosponsor",
       %{grassley: g, miller_meeks: m} do
    assert ids(Calendar.week("federal", ~D[2026-10-26], people: [g.id])) == ["floor-1", "meet-1"]
    assert ids(Calendar.week("federal", ~D[2026-10-26], people: [m.id])) == []
  end

  test "unresolved bill labels stay on the event" do
    [_, %{events: [meeting]} | _] = Calendar.week("federal", ~D[2026-10-26], [])
    assert meeting.unresolved_bill_labels == ["H.R. 999999"]
  end
end
