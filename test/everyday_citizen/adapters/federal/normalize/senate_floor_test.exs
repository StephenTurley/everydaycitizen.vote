defmodule EverydayCitizen.Adapters.Federal.Normalize.SenateFloorTest do
  use ExUnit.Case, async: true

  alias EverydayCitizen.Adapters.Federal.Normalize.SenateFloor
  alias EverydayCitizen.Ingest.Records.{Event, SourceRef}

  # Real Daily Digest "Next Meeting" pages from the Congressional Record.
  @fixtures "test/support/fixtures/federal/congress_gov"
  @busy File.read!("#{@fixtures}/record_next_meeting_2026-09-22.htm")
  @recess File.read!("#{@fixtures}/record_next_meeting_2026-10-22.htm")

  defp event(html, issue_date),
    do:
      SenateFloor.event(html, issue_date, SourceRef.new("https://example.test/d.htm", html), 119)

  test "the next meeting becomes a floor event at its time, titled with the day's program" do
    e = event(@busy, ~D[2026-09-22])

    assert %Event{classification: "floor", body_external_id: "senate", date: ~D[2026-09-23]} = e
    assert e.external_id == "senate-floor-2026-09-23"
    assert e.raw_classification == "record-next-meeting"
    assert e.start_at == ~U[2026-09-23 14:00:00Z]

    assert e.title =~
             "Senate will continue consideration of Thune (for Cruz) Amendment No. 6776, to S. 4668, Protect College Sports Act, post-cloture."

    assert e.title =~ "At 2:15 p.m., Senate will vote on confirmation of the nomination"
    refute e.title =~ "Senate Chamber"
    refute e.title =~ "HOUSE"
    refute e.title =~ "\n"
    assert e.bill_external_ids == ["119-s-4668"]
  end

  test "a pro forma day" do
    e = event(@recess, ~D[2026-10-22])
    assert e.external_id == "senate-floor-2026-10-26"
    assert e.start_at == ~U[2026-10-26 21:30:00Z]
    assert e.title == "Senate will meet in a pro forma session."
    assert e.bill_external_ids == []
  end

  test "a January meeting named in a December issue is in the next year; noon is read" do
    html = """
    <pre>
                           Next Meeting of the SENATE
                         12 noon, Monday, January 4

                                 Senate Chamber
    Program for Monday: Senate will meet in a pro forma session.

                  Next Meeting of the HOUSE OF REPRESENTATIVES
    </pre>
    """

    assert %Event{start_at: ~U[2027-01-04 17:00:00Z]} = event(html, ~D[2026-12-30])
  end

  test "an unreadable time keeps the day as an all-day event" do
    html = """
    <pre>
                           Next Meeting of the SENATE
                    At the call of the Chair, Monday, January 4

                                 Senate Chamber
    Program for Monday: To be announced.
    </pre>
    """

    assert %Event{date: ~D[2027-01-04], start_at: nil, title: "To be announced."} =
             event(html, ~D[2026-12-30])
  end

  test "a page without the next meeting gives nothing" do
    assert event("<pre>Extensions of Remarks</pre>", ~D[2026-10-22]) == nil
  end
end
