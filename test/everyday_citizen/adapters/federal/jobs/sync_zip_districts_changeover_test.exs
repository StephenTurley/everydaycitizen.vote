defmodule EverydayCitizen.Adapters.Federal.Jobs.SyncZipDistrictsChangeoverTest do
  # changes the :federal config's date
  use EverydayCitizen.DataCase, async: false
  use Oban.Testing, repo: EverydayCitizen.Repo

  import EverydayCitizen.FederalDate

  alias EverydayCitizen.Adapters.Federal.Jobs.SyncZipDistricts
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Legislature.PostalDistrict
  alias EverydayCitizen.Repo

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

  test "records the map with the rows" do
    assert :ok = perform_job(SyncZipDistricts, %{})

    assert Repo.all(PostalDistrict) |> Enum.map(& &1.district_map) |> Enum.uniq() == ["119"]
  end

  test "ZIP lookup ignores rows from another map, and rows with none" do
    import Ecto.Query

    assert :ok = perform_job(SyncZipDistricts, %{})
    assert EverydayCitizen.Reps.districts_for_postal_code("52031") == ["IA-1", "IA-2"]

    # the map the next congress sits under
    on(~D[2027-01-10])
    assert EverydayCitizen.Reps.districts_for_postal_code("52031") == []

    # rows loaded before maps were recorded
    on(~D[2026-11-04])

    Repo.update_all(from(p in PostalDistrict, where: p.postal_code == "52031"),
      set: [district_map: nil]
    )

    assert EverydayCitizen.Reps.districts_for_postal_code("52031") == []
  end

  test "does nothing until the sitting congress's file is published" do
    assert :ok = perform_job(SyncZipDistricts, %{})
    before = Repo.aggregate(PostalDistrict, :count)
    flush_paths()

    on(~D[2027-01-10])
    assert :ok = perform_job(SyncZipDistricts, %{})

    refute_received {:path, _}
    assert Repo.aggregate(PostalDistrict, :count) == before

    assert EverydayCitizen.Provenance.last_succeeded_run("federal", "sync_zip_districts").stats ==
             %{"skipped" => "not_published"}
  end

  defp flush_paths do
    receive do
      {:path, _} -> flush_paths()
    after
      0 -> :ok
    end
  end
end
