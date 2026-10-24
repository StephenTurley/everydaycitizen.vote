defmodule EverydayCitizen.Adapters.Federal.Jobs.BackfillBillSummariesTest do
  use EverydayCitizen.DataCase, async: true
  use Oban.Testing, repo: EverydayCitizen.Repo

  alias EverydayCitizen.Adapters.Federal.Jobs.BackfillBillSummaries
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Legislation

  @fixture "test/support/fixtures/federal/govinfo/BILLSTATUS-119hr22.xml"
  @hr_zip "/bulkdata/BILLSTATUS/119/hr/BILLSTATUS-119-hr.zip"

  setup do
    src = Records.SourceRef.new("https://x.test/a", "a")

    for r <- [
          %Records.Jurisdiction{
            key: "federal",
            name: "F",
            classification: "federal",
            source: src
          },
          %Records.LegislativeSession{jurisdiction: "federal", identifier: "119", source: src},
          %Records.Bill{
            jurisdiction: "federal",
            session_identifier: "119",
            external_id: "119-hr-22",
            identifier: "H.R. 22",
            classification: "bill",
            title: "SAVE Act",
            source: src
          }
        ] do
      {:ok, _} = Ingest.write(r, nil)
    end

    {:ok, {_, bytes}} =
      :zip.create(~c"t.zip", [{~c"BILLSTATUS-119hr22.xml", File.read!(@fixture)}], [:memory])

    Req.Test.stub(EverydayCitizen.Federal, fn conn ->
      if conn.request_path == @hr_zip,
        do: Plug.Conn.send_resp(conn, 200, bytes),
        else: Plug.Conn.send_resp(conn, 404, "nope")
    end)

    :ok
  end

  test "fills summaries for stored bills from the bulk files, leaving the bill as it was" do
    assert :ok = run_bulk(BackfillBillSummaries, %{"congress" => 119})

    bill = Legislation.get_bill("federal", "119-hr-22")
    assert %{author: "Congressional Research Service"} = Legislation.latest_summary(bill)
    # summaries only: no actions written
    assert Repo.aggregate(EverydayCitizen.Legislation.BillAction, :count) == 0
    assert EverydayCitizen.Provenance.last_succeeded_run("federal", "backfill_bill_summaries")
  end

  test "it runs by name and is not part of the full ingest" do
    assert {:ok, [{"bill_summaries", BackfillBillSummaries, _}]} =
             EverydayCitizen.Ingest.Jobs.select("bill_summaries")

    refute Enum.any?(EverydayCitizen.Ingest.Jobs.all(), &(elem(&1, 0) == "bill_summaries"))
  end

  defp run_bulk(worker, args, passes \\ 6) do
    case perform_job(worker, args) do
      {:snooze, _} when passes > 0 ->
        Oban.drain_queue(queue: :bulk, with_scheduled: true)
        run_bulk(worker, args, passes - 1)

      other ->
        other
    end
  end
end
