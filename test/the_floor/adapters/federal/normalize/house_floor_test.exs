defmodule TheFloor.Adapters.Federal.Normalize.HouseFloorTest do
  use ExUnit.Case, async: true

  alias TheFloor.Adapters.Federal.Normalize.HouseFloor
  alias TheFloor.Ingest.Records.{Event, SourceRef}

  @xml File.read!("test/support/fixtures/federal/house_docs/floor_week.xml")

  defp source, do: SourceRef.new("https://example.test/week.xml", @xml)
  defp events, do: HouseFloor.events(@xml, source())
  defp by_title(prefix), do: Enum.find(events(), &String.starts_with?(&1.title, prefix))

  test "one floor event per top-level floor item; sub-items are not events" do
    assert length(events()) == 6
    assert Enum.all?(events(), &match?(%Event{classification: "floor", all_day: true}, &1))
    assert Enum.all?(events(), &(&1.body_external_id == "house"))
    assert Enum.all?(events(), &(&1.status == "scheduled"))
    assert Enum.all?(events(), &(&1.jurisdiction == "federal"))
  end

  test "start_at is the week date at midnight Eastern, in UTC" do
    assert Enum.all?(events(), &(&1.start_at == ~U[2026-09-14 04:00:00Z]))
  end

  test "external ids are stable and unique" do
    ids = Enum.map(events(), & &1.external_id)
    assert "house-floor-2026-09-14-h-r-9576" in ids
    assert "house-floor-2026-09-14-s-790" in ids
    assert ids == Enum.uniq(ids)
  end

  test "title keeps the source text with whitespace collapsed" do
    assert by_title("Illegal Red Snapper").title ==
             "Illegal Red Snapper and Tuna Enforcement Act, as amended"
  end

  test "legis-num resolves to a bill external id" do
    assert Enum.find(events(), &(&1.external_id =~ "h-r-9576")).bill_external_ids == [
             "119-hr-9576"
           ]

    assert Enum.find(events(), &(&1.external_id =~ "s-790")).bill_external_ids == ["119-s-790"]

    assert Enum.find(events(), &(&1.external_id =~ "h-con-res-93")).bill_external_ids == [
             "119-hconres-93"
           ]

    assert Enum.find(events(), &(&1.external_id =~ "h-res-1530")).bill_external_ids == [
             "119-hres-1530"
           ]
  end

  test "an embedded label resolves; nothing is left unresolved here" do
    event = Enum.find(events(), &(&1.external_id =~ "senate-amendments"))
    assert event.bill_external_ids == ["119-hr-5334"]
    assert event.raw_bill_labels == []
  end

  test "a legis-num that is not a bill label is kept raw" do
    xml = String.replace(@xml, "<legis-num>S. 283 </legis-num>", "<legis-num>PN 55</legis-num>")
    event = Enum.find(HouseFloor.events(xml, source()), &(&1.external_id =~ "pn-55"))
    assert event.bill_external_ids == []
    assert event.raw_bill_labels == ["PN 55"]
  end

  test "an item with a remove-date is marked removed" do
    xml =
      String.replace(
        @xml,
        ~s(id="409734" add-date="2026-09-08T13:06:15.623" remove-date=""),
        ~s(id="409734" add-date="2026-09-08T13:06:15.623" remove-date="2026-09-10T10:00:00")
      )

    event = Enum.find(HouseFloor.events(xml, source()), &(&1.external_id =~ "s-283"))
    assert event.status == "removed"
  end

  test "empty, malformed and HTML input give no events" do
    assert HouseFloor.events("", source()) == []
    assert HouseFloor.events("<floorschedule></floorschedule>", source()) == []
    assert HouseFloor.events("<html><body>nope</body></html>", source()) == []
    assert HouseFloor.events("<floorschedule", source()) == []
  end
end
