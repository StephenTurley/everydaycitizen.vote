defmodule EverydayCitizen.Adapters.Federal.Normalize.CommitteeMeetingTest do
  use ExUnit.Case, async: true

  alias EverydayCitizen.Adapters.Federal.Normalize.CommitteeMeeting
  alias EverydayCitizen.Ingest.Records.{Event, SourceRef}

  @dir "test/support/fixtures/federal/congress_gov"

  defp json(name), do: @dir |> Path.join(name) |> File.read!() |> Jason.decode!()
  defp source, do: SourceRef.new("https://example.test/meeting.json", "x")
  defp event(name), do: CommitteeMeeting.event(json("committee_meeting_#{name}.json"), source())

  test "a House hearing" do
    assert %Event{} = event = event("house_118809")
    assert event.jurisdiction == "federal"
    assert event.external_id == "meeting-118809"
    assert event.body_external_id == "hspw07"
    assert event.classification == "hearing"
    assert event.raw_classification == "Hearing"
    assert event.status == "scheduled"
    assert event.start_at == ~U[2026-01-13 15:00:00Z]
    assert event.location == "Rayburn House Office Building, 2167"
    assert event.title =~ "Coast Guard Law Enforcement"
    assert event.bill_external_ids == []
    assert %SourceRef{url: "https://example.test/meeting.json"} = event.source
  end

  test "a markup maps to markup and resolves related bills to external ids" do
    event = event("house_119248")
    assert event.classification == "markup"
    assert event.raw_classification == "Markup"
    assert event.bill_external_ids == ["119-hr-8312", "119-hr-8340", "119-hr-8467"]
    assert event.raw_bill_labels == []
  end

  test "a plain Meeting is other, raw type kept" do
    event = event("house_119367")
    assert event.classification == "other"
    assert event.raw_classification == "Meeting"
    assert event.bill_external_ids == ["119-hr-9083", "119-hr-3978", "119-hr-5549"]
  end

  test "Senate Open Hearing is a hearing; nominations are not bills" do
    event = event("senate_338741")
    assert event.classification == "hearing"
    assert event.raw_classification == "Open Hearing"
    assert event.body_external_id == "ssfi00"
    assert event.bill_external_ids == []
    assert event.raw_bill_labels == []
  end

  test "a Senate business meeting is other and links bills of both chambers" do
    event = event("senate_338749")
    assert event.classification == "other"
    assert event.raw_classification == "Open Business Meeting"
    assert event.bill_external_ids == ["119-hr-7022", "119-s-2586", "119-s-3467"]
  end

  test "a canceled meeting keeps its row with the lowercased source status" do
    event = event("house_118405")
    assert event.status == "canceled"
    assert event.classification == "other"
  end

  test "a related bill with an unrecognized type goes to raw_bill_labels" do
    detail = json("committee_meeting_house_119248.json")

    detail =
      put_in(detail, ["committeeMeeting", "relatedItems", "bills"], [
        %{"congress" => 119, "type" => "HR", "number" => "5"},
        %{"congress" => 119, "type" => "ZZ", "number" => "7"}
      ])

    event = CommitteeMeeting.event(detail, source())
    assert event.bill_external_ids == ["119-hr-5"]
    assert event.raw_bill_labels == ["ZZ 7"]
  end

  test "a meeting without location or related items" do
    detail = json("committee_meeting_house_118809.json")
    detail = update_in(detail, ["committeeMeeting"], &Map.delete(&1, "location"))
    assert CommitteeMeeting.event(detail, source()).location == nil
  end

  test "a missing or unparseable date gives a nil start_at" do
    detail = json("committee_meeting_house_118809.json")
    missing = update_in(detail, ["committeeMeeting"], &Map.delete(&1, "date"))
    bad = put_in(detail, ["committeeMeeting", "date"], "soon")
    assert CommitteeMeeting.event(missing, source()).start_at == nil
    assert CommitteeMeeting.event(bad, source()).start_at == nil
  end
end
