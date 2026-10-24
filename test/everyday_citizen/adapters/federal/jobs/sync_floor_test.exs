defmodule EverydayCitizen.Adapters.Federal.Jobs.SyncFloorTest do
  use EverydayCitizen.DataCase, async: true
  use Oban.Testing, repo: EverydayCitizen.Repo

  import Ecto.Query
  import ExUnit.CaptureLog

  alias EverydayCitizen.Adapters.Federal.Jobs.{SyncHouseFloor, SyncSenateFloor}
  alias EverydayCitizen.Calendar.Event
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Provenance
  alias EverydayCitizen.Repo

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
    test "stores the next meeting named in each recent Record issue, idempotently" do
      stub_record()
      assert :ok = perform_job(SyncSenateFloor, %{"congress" => 119})
      assert :ok = perform_job(SyncSenateFloor, %{"congress" => 119})

      events = Repo.all(from e in Event, order_by: e.start_at)
      assert [sep, oct] = events
      assert sep.title =~ "S. 4668"
      assert oct.title == "Senate will meet in a pro forma session."
      assert Repo.preload(oct, :source).source.url =~ "/crec/2026/10/22/172/163/modified/"

      assert Provenance.last_succeeded_run("federal", "sync_senate_floor").stats == %{
               "items" => 2
             }
    end

    test "an issue without a next-meeting section is skipped" do
      stub_record(%{"163" => ~s({"articles": []})})
      assert :ok = perform_job(SyncSenateFloor, %{"congress" => 119})
      assert [%Event{start_at: start}] = Repo.all(Event)
      assert DateTime.compare(start, ~U[2026-09-23 14:00:00Z]) == :eq
    end

    test "a failed API request fails the run" do
      stub_page(500, "")
      assert {:error, {:http_status, 500}} = perform_job(SyncSenateFloor, %{"congress" => 119})
    end
  end

  defp house_xml, do: File.read!("#{@fixtures}/house_docs/floor_week.xml")

  # The Record list, each issue's Daily Digest articles, and the next-meeting pages.
  defp stub_record(articles \\ %{}) do
    dir = "#{@fixtures}/congress_gov"

    Req.Test.stub(EverydayCitizen.Federal, fn conn ->
      body =
        case String.split(conn.request_path, "/", trim: true) do
          ["v3", "daily-congressional-record"] ->
            File.read!("#{dir}/daily_record_list.json")

          ["v3", "daily-congressional-record", "172", issue, "articles"] ->
            articles[issue] || File.read!("#{dir}/daily_record_172_#{issue}_articles.json")

          ["119", "crec", "2026", "09", "22" | _] ->
            File.read!("#{dir}/record_next_meeting_2026-09-22.htm")

          ["119", "crec", "2026", "10", "22" | _] ->
            File.read!("#{dir}/record_next_meeting_2026-10-22.htm")
        end

      Plug.Conn.send_resp(conn, 200, body)
    end)
  end

  defp stub_house(weeks) do
    Req.Test.stub(EverydayCitizen.Federal, fn conn ->
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
    Req.Test.stub(EverydayCitizen.Federal, fn conn -> Plug.Conn.send_resp(conn, status, body) end)
  end

  defp src, do: Records.SourceRef.new("https://example.test/x", "x")

  defp write!(record) do
    {:ok, _} = Ingest.write(record, nil)
    :ok
  end
end
