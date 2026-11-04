defmodule EverydayCitizen.Adapters.Federal.Jobs.SyncSenateFloorChangeoverTest do
  # changes the :federal config's date
  use EverydayCitizen.DataCase, async: false
  use Oban.Testing, repo: EverydayCitizen.Repo

  import EverydayCitizen.FederalDate

  alias EverydayCitizen.Adapters.Federal.Jobs.SyncSenateFloor
  alias EverydayCitizen.Calendar.Event
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Repo

  @dir "test/support/fixtures/federal/congress_gov"
  @src Records.SourceRef.new("https://x.test/senate-floor", "s")

  setup do
    EverydayCitizen.FloorFixtures.iowa!()

    {:ok, _} =
      Ingest.write(
        %Records.Bill{
          jurisdiction: "federal",
          session_identifier: "119",
          external_id: "119-s-4668",
          identifier: "S. 4668",
          classification: "bill",
          title: "A bill",
          from_body_external_id: "senate",
          introduced_on: ~D[2026-06-01],
          source: @src
        },
        nil
      )

    Req.Test.stub(EverydayCitizen.Federal, fn conn ->
      body =
        case String.split(conn.request_path, "/", trim: true) do
          ["v3", "daily-congressional-record"] ->
            File.read!("#{@dir}/daily_record_list.json")

          ["v3", "daily-congressional-record", "172", issue, "articles"] ->
            File.read!("#{@dir}/daily_record_172_#{issue}_articles.json")

          ["119", "crec", "2026", "09", "22" | _] ->
            File.read!("#{@dir}/record_next_meeting_2026-09-22.htm")

          ["119", "crec", "2026", "10", "22" | _] ->
            File.read!("#{@dir}/record_next_meeting_2026-10-22.htm")
        end

      Plug.Conn.send_resp(conn, 200, body)
    end)

    :ok
  end

  test "an issue from before a new congress sits links its bills to that issue's congress" do
    on(~D[2027-01-04])

    assert :ok = perform_job(SyncSenateFloor, %{})

    event =
      Event
      |> Repo.all()
      |> Repo.preload(event_bills: :bill)
      |> Enum.find(&(&1.title =~ "S. 4668"))

    assert [%{bill: %{external_id: "119-s-4668"}}] = event.event_bills
    assert event.unresolved_bill_labels == []
  end
end
