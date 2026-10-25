defmodule EverydayCitizen.CalendarUpcomingTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.Calendar
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records

  @src Records.SourceRef.new("https://x.test/up", "u")
  @now ~U[2026-10-25 12:00:00Z]

  defp event!(id, classification, at, bills) do
    {:ok, _} =
      Ingest.write(
        %Records.Event{
          jurisdiction: "federal",
          body_external_id: "senate",
          external_id: id,
          classification: classification,
          title: "Event #{id}",
          start_at: at,
          bill_external_ids: bills,
          raw_bill_labels: [],
          source: @src
        },
        nil
      )
  end

  setup do
    EverydayCitizen.FloorFixtures.iowa!()
    :ok
  end

  test "items are upcoming floor events with bills, earliest first; next is the earliest floor event" do
    event!("past", "floor", ~U[2026-10-24 14:00:00Z], ["119-s-5"])
    event!("hearing", "hearing", ~U[2026-10-25 13:00:00Z], ["119-s-5"])
    event!("bare", "floor", ~U[2026-10-26 14:00:00Z], [])
    event!("later", "floor", ~U[2026-10-29 14:00:00Z], ["119-s-5"])
    event!("soon", "floor", ~U[2026-10-27 14:00:00Z], ["119-s-5"])

    %{items: items, next: next} = Calendar.upcoming_floor(5, @now)
    assert Enum.map(items, & &1.external_id) == ["soon", "later"]

    assert [%{body: %{name: "Senate"}, event_bills: [%{bill: %{external_id: "119-s-5"}}]} | _] =
             items

    assert next.external_id == "bare"

    assert %{items: [%{external_id: "soon"}]} = Calendar.upcoming_floor(1, @now)
  end

  test "nothing upcoming: no items and no next" do
    event!("past", "floor", ~U[2026-10-24 14:00:00Z], ["119-s-5"])
    assert Calendar.upcoming_floor(5, @now) == %{items: [], next: nil}
  end
end
