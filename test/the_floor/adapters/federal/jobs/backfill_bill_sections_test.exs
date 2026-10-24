defmodule TheFloor.Adapters.Federal.Jobs.BackfillBillSectionsTest do
  use TheFloor.DataCase, async: true
  use Oban.Testing, repo: TheFloor.Repo

  alias TheFloor.Adapters.Federal.BillSections
  alias TheFloor.Adapters.Federal.Jobs.BackfillBillSections
  alias TheFloor.Ingest
  alias TheFloor.Ingest.Records
  alias TheFloor.Legislation.BillVersion

  @xml File.read!("test/support/fixtures/federal/govinfo/BILLS-119hr22ih.xml")

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

    for code <- ~w(ih eh rh) do
      {:ok, _} =
        Ingest.write(
          %Records.BillVersion{
            jurisdiction: "federal",
            bill_external_id: "119-hr-22",
            code: code,
            source: src
          },
          nil
        )
    end

    # stored before sections existed: XML, no sections
    Repo.update_all(BillVersion, set: [xml: @xml])
    Repo.update_all(from(v in BillVersion, where: v.code == "rh"), set: [xml: "<bill><unclosed>"])
    :ok
  end

  test "fills sections for versions with XML, a few at a time, until none are left" do
    assert :ok = perform_job(BackfillBillSections, %{"batch_size" => 2})
    # more remain, so it queued itself again
    assert [_] = all_enqueued(worker: BackfillBillSections)

    assert :ok = perform_job(BackfillBillSections, %{"batch_size" => 2})

    by_code = Repo.all(BillVersion) |> Map.new(&{&1.code, &1.sections})
    assert [%{"enum" => "1."} | _] = by_code["ih"]
    assert [%{"enum" => "1."} | _] = by_code["eh"]
    # unparseable XML is marked done with no sections
    assert by_code["rh"] == []

    assert Repo.all(from v in BillVersion, select: v.sections_version) |> Enum.uniq() ==
             [BillSections.format()]

    assert TheFloor.Legislation.versions_needing_sections(BillSections.format(), 10) == []
  end

  test "versions split by an older format (or none recorded) are split again" do
    old = [%{"kind" => "section", "enum" => "1.", "blocks" => [%{"level" => 0, "text" => "old"}]}]
    Repo.update_all(BillVersion, set: [sections: old, sections_version: 2])
    Repo.update_all(from(v in BillVersion, where: v.code == "ih"), set: [sections_version: nil])
    Repo.update_all(from(v in BillVersion, where: v.code == "eh"), set: [sections_version: 1])

    assert [%{xml: _}, %{xml: _}] =
             needing = TheFloor.Legislation.versions_needing_sections(2, 10)

    assert needing |> Enum.map(& &1.id) |> Enum.sort() ==
             Repo.all(from v in BillVersion, where: v.code in ["ih", "eh"], select: v.id)
             |> Enum.sort()

    assert :ok = perform_job(BackfillBillSections, %{"batch_size" => 5})

    by_code = Repo.all(BillVersion) |> Map.new(&{&1.code, &1})
    refute by_code["ih"].sections == old
    assert by_code["ih"].sections_version == BillSections.format()
    # already on the current format: left alone
    assert by_code["rh"].sections == old
  end

  test "a version that fails to store does not stop the others" do
    Repo.update_all(from(v in BillVersion, where: v.code == "eh"),
      set: [xml: "<bill><section><enum>1.</enum><text>a&#0;b</text></section></bill>"]
    )

    assert :ok = perform_job(BackfillBillSections, %{"batch_size" => 5})

    by_code = Repo.all(BillVersion) |> Map.new(&{&1.code, &1})
    assert [%{"enum" => "1."} | _] = by_code["ih"].sections
    assert Enum.all?(Map.values(by_code), &(&1.sections_version == BillSections.format()))
  end

  test "it runs by name only" do
    assert {:ok, [{"bill_sections", BackfillBillSections, _}]} =
             TheFloor.Ingest.Jobs.select("bill_sections")

    refute Enum.any?(TheFloor.Ingest.Jobs.all(), &(elem(&1, 0) == "bill_sections"))
  end
end
