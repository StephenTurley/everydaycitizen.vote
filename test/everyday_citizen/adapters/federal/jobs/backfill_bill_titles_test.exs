defmodule EverydayCitizen.Adapters.Federal.Jobs.BackfillBillTitlesTest do
  use EverydayCitizen.DataCase, async: true
  use Oban.Testing, repo: EverydayCitizen.Repo

  import Ecto.Query

  alias EverydayCitizen.Adapters.Federal.Jobs.{BackfillBillTitles, SyncBillTitles}
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Legislation.BillTitle
  alias EverydayCitizen.Repo

  @args %{"congress" => 119, "type" => "hr", "number" => "22"}

  setup do
    src = Records.SourceRef.new("https://api.congress.gov/v3/bill/119/hr/22", "a")

    {:ok, _} =
      Ingest.write(
        %Records.Jurisdiction{key: "federal", name: "F", classification: "federal", source: src},
        nil
      )

    {:ok, _} =
      Ingest.write(
        %Records.LegislativeSession{jurisdiction: "federal", identifier: "119", source: src},
        nil
      )

    for {id, label} <- [{"119-hr-22", "H.R. 22"}, {"119-s-5", "S. 5"}] do
      {:ok, _} =
        Ingest.write(
          %Records.Bill{
            jurisdiction: "federal",
            session_identifier: "119",
            external_id: id,
            identifier: label,
            classification: "bill",
            title: "T",
            source: src
          },
          nil
        )
    end

    :ok
  end

  defp stub_titles(status, body) do
    Req.Test.stub(EverydayCitizen.Federal, fn conn ->
      Plug.Conn.send_resp(conn, status, body)
    end)
  end

  test "backfill enqueues one titles job per stored bill on the backfill queue" do
    assert :ok = perform_job(BackfillBillTitles, %{})
    assert length(all_enqueued(worker: SyncBillTitles)) == 2

    assert_enqueued(worker: SyncBillTitles, queue: "backfill", args: @args)

    assert_enqueued(
      worker: SyncBillTitles,
      args: %{"congress" => 119, "type" => "s", "number" => "5"}
    )
  end

  test "a bill with stored titles is not enqueued, one without is" do
    src = Records.SourceRef.new("https://x.test/t", "t")

    {:ok, _} =
      Ingest.write(
        %Records.BillTitles{
          jurisdiction: "federal",
          bill_external_id: "119-hr-22",
          titles: [%{title: "SAVE Act", kind: "short"}],
          source: src
        },
        nil
      )

    assert :ok = perform_job(BackfillBillTitles, %{})

    assert [%{args: %{"type" => "s", "number" => "5"}}] = all_enqueued(worker: SyncBillTitles)
  end

  test "a titles job writes the titles" do
    stub_titles(
      200,
      File.read!("test/support/fixtures/federal/congress_gov/bill_119_hr_22/titles.json")
    )

    assert :ok = perform_job(SyncBillTitles, @args)

    assert "Safeguard American Voter Eligibility Act" in Repo.all(
             from t in BillTitle, select: t.title
           )
  end

  test "a titles job for a bill the source no longer has is done, not retried" do
    stub_titles(404, "{}")
    assert :ok = perform_job(SyncBillTitles, @args)
    assert Repo.all(BillTitle) == []
  end

  test "a titles job fails on other errors so it is retried" do
    stub_titles(500, "{}")
    assert {:error, _} = perform_job(SyncBillTitles, @args)
  end
end
