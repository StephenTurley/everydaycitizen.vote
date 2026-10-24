defmodule EverydayCitizen.Adapters.Federal.Normalize.SenateFloorTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias EverydayCitizen.Adapters.Federal.Normalize.SenateFloor
  alias EverydayCitizen.Ingest.Records.{Event, SourceRef}

  # Synthetic fixture: senate.gov blocks this machine, so the parser is unverified
  # against the live page.
  @html File.read!("test/support/fixtures/federal/senate/floor_schedule_SYNTHETIC.htm")

  defp source, do: SourceRef.new("https://example.test/floor_schedule.htm", @html)
  defp events, do: SenateFloor.events(@html, source(), 119)

  test "one floor event per scheduled day, headings only" do
    assert [mon, tue, wed] = events()
    assert Enum.all?([mon, tue, wed], &match?(%Event{classification: "floor", all_day: true}, &1))
    assert Enum.all?([mon, tue, wed], &(&1.body_external_id == "senate"))

    assert [mon.external_id, tue.external_id, wed.external_id] ==
             ["senate-floor-2026-10-19", "senate-floor-2026-10-20", "senate-floor-2026-10-21"]

    assert mon.start_at == ~U[2026-10-19 04:00:00Z]
    assert mon.status == "scheduled"
  end

  test "bills are extracted from the day's text" do
    assert [mon, tue, wed] = events()
    assert mon.bill_external_ids == ["119-s-1234", "119-hr-5678", "119-sjres-12"]
    assert tue.bill_external_ids == []
    assert wed.bill_external_ids == ["119-sres-99", "119-hres-40", "119-s-1234"]
  end

  test "title is the day's source text" do
    assert [mon | _] = events()
    assert mon.title =~ "Convene at 3:00 p.m."
    refute mon.title =~ "Tuesday"
  end

  test "missing structure returns [] and logs a warning" do
    log =
      capture_log(fn ->
        assert SenateFloor.events("<html><body><p>hi</p></body></html>", source(), 119) == []
      end)

    assert log =~ "senate floor"
    capture_log(fn -> assert SenateFloor.events("", source(), 119) == [] end)
  end
end
