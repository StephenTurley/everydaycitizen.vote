defmodule EverydayCitizen.Adapters.Federal.Jobs.BackfillBillHistoryTest do
  use EverydayCitizen.DataCase, async: true
  use Oban.Testing, repo: EverydayCitizen.Repo

  alias EverydayCitizen.Adapters.Federal.Jobs.{BackfillBillHistory, SyncBill}
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records

  test "re-syncs each bill with two or more text versions" do
    EverydayCitizen.FloorFixtures.iowa!()
    src = Records.SourceRef.new("https://x.test/v", "v")

    for code <- ["is", "es"] do
      {:ok, _} =
        Ingest.write(
          %Records.BillVersion{
            jurisdiction: "federal",
            bill_external_id: "119-s-5",
            code: code,
            source: src
          },
          nil
        )
    end

    assert :ok = perform_job(BackfillBillHistory, %{})

    assert [%{args: %{"congress" => 119, "type" => "s", "number" => "5"}}] =
             all_enqueued(worker: SyncBill)
  end
end
