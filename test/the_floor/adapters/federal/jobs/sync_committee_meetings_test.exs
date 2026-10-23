defmodule TheFloor.Adapters.Federal.Jobs.SyncCommitteeMeetingsTest do
  use TheFloor.DataCase, async: true
  use Oban.Testing, repo: TheFloor.Repo

  alias TheFloor.Adapters.Federal.Jobs.{SyncCommitteeMeeting, SyncCommitteeMeetings}
  alias TheFloor.Calendar.{Event, EventBill}
  alias TheFloor.Ingest
  alias TheFloor.Ingest.Records
  alias TheFloor.Repo

  @dir "test/support/fixtures/federal/congress_gov"

  setup do
    write!(%Records.Jurisdiction{
      key: "federal",
      name: "Federal",
      classification: "federal",
      source: src()
    })

    write!(%Records.LegislativeSession{jurisdiction: "federal", identifier: "119", source: src()})

    write!(%Records.Body{
      jurisdiction: "federal",
      external_id: "hspw07",
      name: "Transportation and Infrastructure",
      classification: "committee",
      source: src()
    })

    :ok
  end

  describe "SyncCommitteeMeeting" do
    test "stores the event under its committee, idempotently" do
      stub_detail("house_118809")
      assert :ok = perform_job(SyncCommitteeMeeting, args("house", "118809"))

      event = Repo.one!(Event) |> Repo.preload(:body)
      assert event.external_id == "meeting-118809"
      assert event.body.external_id == "hspw07"
      assert event.classification == "hearing"
      assert event.start_at == ~U[2026-01-13 15:00:00.000000Z]

      assert :ok = perform_job(SyncCommitteeMeeting, args("house", "118809"))
      assert Repo.aggregate(Event, :count) == 1
    end

    test "an unknown committee code stores the event without a body" do
      stub_detail("senate_338741")
      assert :ok = perform_job(SyncCommitteeMeeting, args("senate", "338741"))
      assert Repo.one!(Event).body_id == nil
    end

    test "links stored bills and keeps the rest unresolved" do
      write!(%Records.Bill{
        jurisdiction: "federal",
        session_identifier: "119",
        external_id: "119-hr-8312",
        identifier: "H.R. 8312",
        classification: "bill",
        title: "Example",
        source: src()
      })

      stub_detail("house_119248")
      assert :ok = perform_job(SyncCommitteeMeeting, args("house", "119248"))

      event = Repo.one!(Event)
      assert Repo.aggregate(EventBill, :count) == 1
      assert Enum.sort(event.unresolved_bill_labels) == ["119-hr-8340", "119-hr-8467"]
    end

    @tag :capture_log
    test "a meeting without a date is skipped with a warning, not failed" do
      detail = @dir |> Path.join("committee_meeting_house_118809.json") |> File.read!()

      detail =
        detail |> Jason.decode!() |> update_in(["committeeMeeting"], &Map.delete(&1, "date"))

      Req.Test.stub(TheFloor.Federal, fn conn -> Req.Test.json(conn, detail) end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert :ok = perform_job(SyncCommitteeMeeting, args("house", "118809"))
        end)

      assert log =~ "118809"
      assert Repo.aggregate(Event, :count) == 0
    end

    test "a canceled meeting is kept with its status" do
      stub_detail("house_118405")
      assert :ok = perform_job(SyncCommitteeMeeting, args("house", "118405"))
      assert Repo.one!(Event).status == "canceled"
    end
  end

  describe "SyncCommitteeMeetings" do
    test "enqueues a detail job per listed meeting in both chambers" do
      stub_lists()
      assert :ok = perform_job(SyncCommitteeMeetings, %{"congress" => 119})

      assert enqueued() == [
               {"house", "338781"},
               {"house", "338787"},
               {"house", "338788"},
               {"senate", "338781"},
               {"senate", "338787"},
               {"senate", "338788"}
             ]
    end

    test "passes the cursor as fromDateTime" do
      {:ok, run} = TheFloor.Provenance.start_run("federal", "sync_committee_meetings")
      {:ok, _} = TheFloor.Provenance.finish_run(run, :succeeded, %{}, nil)
      run |> Ecto.Changeset.change(started_at: ~U[2026-10-01 12:30:00.000000Z]) |> Repo.update!()
      test_pid = self()

      Req.Test.stub(TheFloor.Federal, fn conn ->
        send(test_pid, {:query, conn.params})
        Req.Test.json(conn, %{"committeeMeetings" => [], "pagination" => %{"count" => 0}})
      end)

      assert :ok = perform_job(SyncCommitteeMeetings, %{"congress" => 119})
      assert_received {:query, %{"fromDateTime" => "2026-10-01T12:30:00Z"}}
    end

    test "re-fetches stored meetings dated in the next 14 days, not later or past ones" do
      now = DateTime.utc_now()
      store_event!("501", "house", DateTime.add(now, 3 * 86_400))
      store_event!("502", "senate", DateTime.add(now, 30 * 86_400))
      store_event!("503", "house", DateTime.add(now, -3 * 86_400))

      Req.Test.stub(TheFloor.Federal, fn conn ->
        Req.Test.json(conn, %{"committeeMeetings" => [], "pagination" => %{"count" => 0}})
      end)

      assert :ok = perform_job(SyncCommitteeMeetings, %{"congress" => 119})
      assert enqueued() == [{"house", "501"}]
    end
  end

  defp enqueued do
    Enum.sort(
      for %{args: %{"chamber" => c, "event_id" => id}} <-
            all_enqueued(worker: SyncCommitteeMeeting),
          do: {c, id}
    )
  end

  defp store_event!(id, chamber, start_at) do
    write!(%Records.Event{
      jurisdiction: "federal",
      external_id: "meeting-#{id}",
      classification: "hearing",
      start_at: start_at,
      source:
        Records.SourceRef.new(
          "https://api.congress.gov/v3/committee-meeting/119/#{chamber}/#{id}?format=json",
          "x"
        )
    })
  end

  defp args(chamber, id), do: %{"congress" => 119, "chamber" => chamber, "event_id" => id}

  defp stub_lists do
    body = @dir |> Path.join("committee_meeting_list.json") |> File.read!()

    Req.Test.stub(TheFloor.Federal, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, body)
    end)
  end

  defp stub_detail(name) do
    body = @dir |> Path.join("committee_meeting_#{name}.json") |> File.read!()

    Req.Test.stub(TheFloor.Federal, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, body)
    end)
  end

  defp src, do: Records.SourceRef.new("https://example.test/x", "x")

  defp write!(record) do
    {:ok, _} = Ingest.write(record, nil)
    :ok
  end
end
