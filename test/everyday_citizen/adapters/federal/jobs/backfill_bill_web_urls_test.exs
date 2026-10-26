defmodule EverydayCitizen.Adapters.Federal.Jobs.BackfillBillWebUrlsTest do
  use EverydayCitizen.DataCase, async: true
  use Oban.Testing, repo: EverydayCitizen.Repo

  alias EverydayCitizen.Adapters.Federal.Jobs.BackfillBillWebUrls
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Legislation.Bill

  setup do
    src = Records.SourceRef.new("https://api.congress.gov/v3/bill/119/s/5", "a")

    {:ok, _} =
      Ingest.write(
        %Records.Jurisdiction{
          key: "federal",
          name: "F",
          classification: "federal",
          time_zone: "America/New_York",
          source: src
        },
        nil
      )

    {:ok, _} =
      Ingest.write(
        %Records.LegislativeSession{jurisdiction: "federal", identifier: "119", source: src},
        nil
      )

    for {id, label} <- [{"119-s-5", "S. 5"}, {"119-hres-9", "H.Res. 9"}, {"119-hr-1", "H.R. 1"}] do
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

    Repo.update_all(from(b in Bill, where: b.external_id == "119-hr-1"),
      set: [web_url: "https://kept.test/"]
    )

    :ok
  end

  test "fills the official page of bills that have none, a batch at a time, and leaves others" do
    assert :ok = perform_job(BackfillBillWebUrls, %{"batch_size" => 1})
    assert [_] = all_enqueued(worker: BackfillBillWebUrls)
    assert :ok = perform_job(BackfillBillWebUrls, %{"batch_size" => 1})

    urls = Repo.all(Bill) |> Map.new(&{&1.external_id, &1.web_url})
    assert urls["119-s-5"] == "https://www.congress.gov/bill/119th-congress/senate-bill/5"
    assert urls["119-hres-9"] == "https://www.congress.gov/bill/119th-congress/house-resolution/9"
    assert urls["119-hr-1"] == "https://kept.test/"
  end

  test "it runs by name only" do
    assert {:ok, [{"bill_web_urls", BackfillBillWebUrls, _}]} =
             EverydayCitizen.Ingest.Jobs.select("bill_web_urls")
  end
end
