defmodule EverydayCitizen.Ingest.Writer.CalendarTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.Calendar
  alias EverydayCitizen.Calendar.{Event, EventBill}
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Repo

  @jur "fed"

  setup do
    write!(%Records.Jurisdiction{
      key: @jur,
      name: "Fed",
      classification: "federal",
      source: source_ref()
    })

    write!(%Records.LegislativeSession{
      jurisdiction: @jur,
      identifier: "119",
      source: source_ref()
    })

    write!(%Records.Body{
      jurisdiction: @jur,
      external_id: "lower",
      name: "Lower",
      classification: "chamber",
      source: source_ref()
    })

    for n <- 1..2 do
      write!(%Records.Bill{
        jurisdiction: @jur,
        session_identifier: "119",
        external_id: "119-hr-#{n}",
        identifier: "HR #{n}",
        classification: "bill",
        title: "Bill #{n}",
        source: source_ref()
      })
    end

    :ok
  end

  defp write!(record) do
    {:ok, row} = Ingest.write(record, nil)
    row
  end

  defp event(attrs \\ []) do
    struct!(
      %Records.Event{
        jurisdiction: @jur,
        body_external_id: "lower",
        external_id: "ev-1",
        classification: "hearing",
        raw_classification: "Hearing",
        title: "A hearing",
        start_at: ~U[2026-03-01 15:00:00Z],
        all_day: false,
        location: "Room 1",
        bill_external_ids: ["119-hr-1", "119-hr-404"],
        raw_bill_labels: ["H.R. 99ish"],
        source: source_ref()
      },
      attrs
    )
  end

  test "event links known bills and keeps unknown labels" do
    e = write!(event())
    assert e.status == "scheduled"
    assert Enum.sort(e.unresolved_bill_labels) == ["119-hr-404", "H.R. 99ish"]
    assert Repo.aggregate(EventBill, :count) == 1
  end

  test "re-ingest replaces bill links and is idempotent" do
    write!(event())
    write!(event(bill_external_ids: ["119-hr-2"], raw_bill_labels: [], status: "cancelled"))
    assert Repo.aggregate(Event, :count) == 1
    assert [%{status: "cancelled", unresolved_bill_labels: []}] = Repo.all(Event)
    assert [eb] = Repo.all(EventBill)
    assert eb.bill_id == EverydayCitizen.Legislation.get_bill(@jur, "119-hr-2").id
  end

  test "event without body and unknown body error" do
    assert write!(event(body_external_id: nil)).body_id == nil
    assert {:error, {:unknown_body, "nope"}} = Ingest.write(event(body_external_id: "nope"), nil)
  end

  test "list_events returns events in range ordered by start" do
    write!(event())
    write!(event(external_id: "ev-2", start_at: ~U[2026-03-02 15:00:00Z]))
    write!(event(external_id: "ev-3", start_at: ~U[2026-04-02 15:00:00Z]))
    list = Calendar.list_events(~U[2026-03-01 00:00:00Z], ~U[2026-03-10 00:00:00Z])
    assert Enum.map(list, & &1.external_id) == ["ev-1", "ev-2"]
  end

  test "unknown classification is rejected by changeset" do
    cs = Event.changeset(%Event{}, %{classification: "party"})
    assert %{classification: [_]} = errors_on(cs)
  end
end
