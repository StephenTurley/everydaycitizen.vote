defmodule TheFloor.Adapters.Federal.Jobs.SyncBillsBulkTest do
  use TheFloor.DataCase, async: true
  use Oban.Testing, repo: TheFloor.Repo

  import Ecto.Query

  alias TheFloor.Adapters.Federal.Jobs.{BackfillBillText, SyncBill, SyncBills, SyncBillText}
  alias TheFloor.Adapters.Federal.Jobs.SyncCongress
  alias TheFloor.Ingest
  alias TheFloor.Ingest.Records.{Person, SourceRef}
  alias TheFloor.Legislation.{Bill, BillAction, BillVersion, Sponsorship}
  alias TheFloor.Provenance

  @moduletag :capture_log

  @congress_gov "test/support/fixtures/federal/congress_gov"
  @bulk_fixture "test/support/fixtures/federal/govinfo/BILLSTATUS-119hr22.xml"
  @hr_zip "/bulkdata/BILLSTATUS/119/hr/BILLSTATUS-119-hr.zip"
  @entry_url "https://www.govinfo.gov/bulkdata/BILLSTATUS/119/hr/BILLSTATUS-119hr22.xml"

  defp zip(entries) do
    files = for {name, body} <- entries, do: {String.to_charlist(name), body}
    {:ok, {_, bytes}} = :zip.create(~c"t.zip", files, [:memory])
    bytes
  end

  # Serves the congress, the bill listing (API path) and the given bulk zips; any
  # other bulk zip is a 404.
  defp stub(zips) do
    Req.Test.stub(TheFloor.Federal, fn conn ->
      case {conn.host, conn.request_path} do
        {"api.congress.gov", "/v3/congress/119"} ->
          Plug.Conn.send_resp(conn, 200, File.read!("#{@congress_gov}/congress_119.json"))

        {"api.congress.gov", "/v3/bill/119"} ->
          send(self(), :api_listing)
          Plug.Conn.send_resp(conn, 200, ~s({"bills": [], "pagination": {"count": 0}}))

        {"www.govinfo.gov", path} ->
          send(self(), {:bulk, path})
          bulk_response(conn, Map.fetch(zips, path))
      end
    end)
  end

  defp bulk_response(conn, {:ok, bytes}), do: Plug.Conn.send_resp(conn, 200, bytes)
  defp bulk_response(conn, :error), do: Plug.Conn.send_resp(conn, 404, "nope")

  setup do
    stub(%{})
    assert :ok = perform_job(SyncCongress, %{"congress" => 119})

    source = SourceRef.new("https://example.test/people", "p")

    cosponsors =
      "#{@congress_gov}/bill_119_hr_22/cosponsors.json" |> File.read!() |> JSON.decode!()

    for id <- ["R000614" | Enum.map(cosponsors["cosponsors"], & &1["bioguideId"])] do
      {:ok, _} =
        Ingest.write(%Person{identifiers: [{"bioguide", id}], name: id, source: source}, nil)
    end

    {:ok, run} = Provenance.start_run("federal", "sync_members")
    {:ok, _} = Provenance.finish_run(run, :succeeded, %{}, nil)
    :ok
  end

  test "first run loads bills from the bulk zip and records a sync_bills run" do
    stub(%{
      @hr_zip =>
        zip([
          {"BILLSTATUS-119hr22.xml", File.read!(@bulk_fixture)},
          {"BILLSTATUS-119hr7.xml", "<billStatus><bill><unclosed>"}
        ])
    })

    assert :ok = perform_job(SyncBills, %{"congress" => 119})
    refute_received :api_listing

    bill = Bill |> Repo.get_by!(external_id: "119-hr-22") |> Repo.preload(:source)
    assert bill.source.url == @entry_url
    assert Repo.aggregate(where(BillAction, bill_id: ^bill.id), :count) == 19

    # sponsor + the 5 cosponsors stored as people; the other 105 are skipped
    assert Repo.aggregate(where(Sponsorship, bill_id: ^bill.id), :count) == 6

    assert Repo.all(from v in BillVersion, where: v.bill_id == ^bill.id, select: v.xml_url)
           |> Enum.sort() == [
             "https://www.govinfo.gov/content/pkg/BILLS-119hr22eh/xml/BILLS-119hr22eh.xml",
             "https://www.govinfo.gov/content/pkg/BILLS-119hr22ih/xml/BILLS-119hr22ih.xml"
           ]

    assert [%{args: %{"congress" => 119, "type" => "hr", "number" => "7"}}] =
             all_enqueued(worker: SyncBill)

    assert [_] = all_enqueued(worker: BackfillBillText)
    assert [] = all_enqueued(worker: SyncBillText)

    run = Provenance.last_succeeded_run("federal", "sync_bills")
    assert run.stats["source"] == "bulk"
    assert run.stats["written"] == 1
    assert run.stats["fallback"] == 1
  end

  test "an entry that raises falls back to the API and the run continues" do
    # textVersions with a non-item child reads as a map, which the fix-up cannot walk.
    raising = """
    <billStatus><bill><number>8</number><type>HR</type><congress>119</congress>
    <title>T</title><textVersions><odd><url>x</url></odd></textVersions></bill></billStatus>
    """

    stub(%{
      @hr_zip =>
        zip([
          {"BILLSTATUS-119hr8.xml", raising},
          {"BILLSTATUS-119hr22.xml", File.read!(@bulk_fixture)}
        ])
    })

    assert :ok = perform_job(SyncBills, %{"congress" => 119})
    assert Repo.get_by(Bill, external_id: "119-hr-22")

    assert [%{args: %{"type" => "hr", "number" => "8"}}] = all_enqueued(worker: SyncBill)
    assert Provenance.last_succeeded_run("federal", "sync_bills").stats["fallback"] == 1
  end

  test "a later run uses the API listing with the cursor" do
    {:ok, run} = Provenance.start_run("federal", "sync_bills")
    {:ok, _} = Provenance.finish_run(run, :succeeded, %{}, nil)

    assert :ok = perform_job(SyncBills, %{"congress" => 119})
    assert_received :api_listing
    refute_received {:bulk, _}
  end

  test "a first run that writes no bills fails and keeps the cursor unset" do
    assert {:error, :no_bulk_bills} = perform_job(SyncBills, %{"congress" => 119})
    refute Provenance.last_succeeded_run("federal", "sync_bills")
  end

  test "bills snooze until a sync_members run has succeeded" do
    Repo.delete_all(where(Provenance.IngestRun, job: "sync_members"))
    assert {:snooze, 300} = perform_job(SyncBills, %{"congress" => 119})
    refute_received {:bulk, _}
  end
end
