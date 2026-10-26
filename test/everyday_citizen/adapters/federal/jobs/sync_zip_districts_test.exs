defmodule EverydayCitizen.Adapters.Federal.Jobs.SyncZipDistrictsTest do
  use EverydayCitizen.DataCase, async: true
  use Oban.Testing, repo: EverydayCitizen.Repo

  alias EverydayCitizen.Adapters.Federal.Jobs.SyncZipDistricts
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records

  setup do
    src = Records.SourceRef.new("https://x.test/a", "a")

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

    Req.Test.stub(EverydayCitizen.Federal, fn conn ->
      send(self(), {:path, conn.request_path})

      Plug.Conn.send_resp(
        conn,
        200,
        File.read!("test/support/fixtures/federal/census/cd119_zcta_sample.txt")
      )
    end)

    :ok
  end

  test "downloads the congress's ZIP-to-district file and stores it" do
    assert :ok = perform_job(SyncZipDistricts, %{})

    assert_received {:path,
                     "/geo/docs/maps-data/data/rel2020/cd-sld/tab20_cd11920_zcta520_natl.txt"}

    assert EverydayCitizen.Reps.districts_for_postal_code("52031") == ["IA-1", "IA-2"]
    assert EverydayCitizen.Provenance.last_succeeded_run("federal", "sync_zip_districts")
  end

  test "it runs by name only" do
    assert {:ok, [{"zip_districts", SyncZipDistricts, _}]} =
             EverydayCitizen.Ingest.Jobs.select("zip_districts")

    refute Enum.any?(EverydayCitizen.Ingest.Jobs.all(), &(elem(&1, 0) == "zip_districts"))
  end
end
