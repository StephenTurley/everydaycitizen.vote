defmodule TheFloor.Adapters.Federal.Jobs.SyncFloorTest do
  use TheFloor.DataCase, async: true
  use Oban.Testing, repo: TheFloor.Repo

  import ExUnit.CaptureLog

  alias TheFloor.Adapters.Federal.Jobs.{SyncHouseFloor, SyncSenateFloor}
  alias TheFloor.Calendar.Event
  alias TheFloor.Ingest
  alias TheFloor.Ingest.Records
  alias TheFloor.Provenance
  alias TheFloor.Repo

  @fixtures "test/support/fixtures/federal"

  setup do
    write!(%Records.Jurisdiction{
      key: "federal",
      name: "Federal",
      classification: "federal",
      source: src()
    })

    write!(%Records.LegislativeSession{jurisdiction: "federal", identifier: "119", source: src()})

    for id <- ["house", "senate"] do
      write!(%Records.Body{
        jurisdiction: "federal",
        external_id: id,
        name: id,
        classification: "chamber",
        source: src()
      })
    end

    :ok
  end

  describe "SyncHouseFloor" do
    test "fetches the current and next week, stores events idempotently" do
      stub_house(%{"20260914" => {:xml, house_xml()}, "20260921" => {:html, "<html>x</html>"}})
      args = %{"date" => "2026-09-16", "congress" => 119}

      assert :ok = perform_job(SyncHouseFloor, args)
      assert Repo.aggregate(Event, :count) == 6
      assert :ok = perform_job(SyncHouseFloor, args)
      assert Repo.aggregate(Event, :count) == 6

      run = Provenance.last_succeeded_run("federal", "sync_house_floor")
      assert run.stats == %{"weeks" => 1, "items" => 6}
    end

    test "an HTML 200 or a 404 week means no events and success" do
      stub_house(%{
        "20260914" => {:html, "<!DOCTYPE html><html></html>"},
        "20260921" => {:status, 404}
      })

      assert :ok = perform_job(SyncHouseFloor, %{"date" => "2026-09-16", "congress" => 119})
      assert Repo.aggregate(Event, :count) == 0
    end

    test "an XML week that parses to zero items warns and records items 0" do
      stub_house(%{
        "20260914" => {:xml, "<floorschedule week-date=\"2026-09-14\"/>"},
        "20260921" => {:status, 404}
      })

      log =
        capture_log(fn ->
          assert :ok = perform_job(SyncHouseFloor, %{"date" => "2026-09-16", "congress" => 119})
        end)

      assert log =~ "parsed to 0 items"
      assert Provenance.last_succeeded_run("federal", "sync_house_floor").stats["items"] == 0
    end

    test "other HTTP failures fail the run" do
      stub_house(%{"20260914" => {:status, 500}, "20260921" => {:status, 500}})

      assert {:error, {:http_status, 500}} =
               perform_job(SyncHouseFloor, %{"date" => "2026-09-16", "congress" => 119})
    end
  end

  describe "SyncSenateFloor" do
    test "stores one event per day, idempotently" do
      stub_page(200, senate_html())
      assert :ok = perform_job(SyncSenateFloor, %{"congress" => 119})
      assert Repo.aggregate(Event, :count) == 3
      assert :ok = perform_job(SyncSenateFloor, %{"congress" => 119})
      assert Repo.aggregate(Event, :count) == 3

      assert Provenance.last_succeeded_run("federal", "sync_senate_floor").stats == %{
               "items" => 3
             }
    end

    test "a page that parses to nothing warns and records items 0" do
      stub_page(200, "<html><body><p>Maintenance</p></body></html>")

      log =
        capture_log(fn -> assert :ok = perform_job(SyncSenateFloor, %{"congress" => 119}) end)

      assert log =~ "parsed to 0 items"

      assert Provenance.last_succeeded_run("federal", "sync_senate_floor").stats == %{
               "items" => 0
             }
    end

    test "a 403 fails the run" do
      stub_page(403, "Forbidden")
      assert {:error, {:http_status, 403}} = perform_job(SyncSenateFloor, %{"congress" => 119})
    end
  end

  defp house_xml, do: File.read!("#{@fixtures}/house_docs/floor_week.xml")
  defp senate_html, do: File.read!("#{@fixtures}/senate/floor_schedule_SYNTHETIC.htm")

  defp stub_house(weeks) do
    Req.Test.stub(TheFloor.Federal, fn conn ->
      [_, stamp] = Regex.run(~r"/billsthisweek/(\d{8})/", conn.query_string |> URI.decode())

      case Map.fetch!(weeks, stamp) do
        {:xml, body} ->
          conn
          |> Plug.Conn.put_resp_content_type("application/xml")
          |> Plug.Conn.send_resp(200, body)

        {:html, body} ->
          conn |> Plug.Conn.put_resp_content_type("text/html") |> Plug.Conn.send_resp(200, body)

        {:status, status} ->
          Plug.Conn.send_resp(conn, status, "")
      end
    end)
  end

  defp stub_page(status, body) do
    Req.Test.stub(TheFloor.Federal, fn conn -> Plug.Conn.send_resp(conn, status, body) end)
  end

  defp src, do: Records.SourceRef.new("https://example.test/x", "x")

  defp write!(record) do
    {:ok, _} = Ingest.write(record, nil)
    :ok
  end
end
