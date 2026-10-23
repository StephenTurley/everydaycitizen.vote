defmodule TheFloor.Adapters.Federal.Jobs.BackfillBillTextTest do
  use TheFloor.DataCase, async: true
  use Oban.Testing, repo: TheFloor.Repo

  alias TheFloor.Adapters.Federal.Jobs.{BackfillBillText, SyncBillText}
  alias TheFloor.Ingest
  alias TheFloor.Ingest.Records
  alias TheFloor.Legislation
  alias TheFloor.Provenance

  @fixture "test/support/fixtures/federal/govinfo/BILLS-119hr22ih.xml"
  @zip_path "/bulkdata/BILLS/119/1/hr/BILLS-119-1-hr.zip"

  setup do
    write!(%Records.Jurisdiction{
      key: "federal",
      name: "Federal",
      classification: "federal",
      source: src()
    })

    write!(%Records.LegislativeSession{jurisdiction: "federal", identifier: "119", source: src()})

    write!(%Records.LegislativeSession{
      jurisdiction: "federal",
      identifier: "119-1",
      parent_identifier: "119",
      source: src()
    })

    write!(%Records.Body{
      jurisdiction: "federal",
      external_id: "house",
      name: "House",
      classification: "chamber",
      source: src()
    })

    write!(%Records.Bill{
      jurisdiction: "federal",
      session_identifier: "119",
      external_id: "119-hr-22",
      identifier: "HR 22",
      classification: "bill",
      title: "SAVE Act",
      from_body_external_id: "house",
      source: src()
    })

    for code <- ~w(ih eh) do
      write!(%Records.BillVersion{
        jurisdiction: "federal",
        bill_external_id: "119-hr-22",
        code: code,
        source: src()
      })
    end

    :ok
  end

  defp src, do: Records.SourceRef.new("https://x.test/a", "a")

  defp write!(record) do
    {:ok, row} = Ingest.write(record, nil)
    row
  end

  defp zip(entries) do
    files = for {name, body} <- entries, do: {String.to_charlist(name), body}
    {:ok, {_, bytes}} = :zip.create(~c"t.zip", files, [:memory])
    bytes
  end

  defp stub(zip_bytes) do
    Req.Test.stub(TheFloor.Federal, fn conn ->
      if conn.request_path == @zip_path,
        do: Plug.Conn.send_resp(conn, 200, zip_bytes),
        else: Plug.Conn.send_resp(conn, 404, "nope")
    end)
  end

  defp version(code),
    do: Legislation.get_version(Legislation.get_bill("federal", "119-hr-22"), code)

  test "stores text for versions in the zip and falls back for the rest" do
    stub(zip([{"BILLS-119hr22ih.xml", File.read!(@fixture)}, {"BILLS-119hr999ih.xml", "<x/>"}]))

    assert :ok = perform_job(BackfillBillText, %{"congress" => 119})

    ih = Repo.preload(version("ih"), :text_source)
    assert ih.plain_text =~ "Short title"

    assert ih.text_source.url ==
             "https://www.govinfo.gov/bulkdata/BILLS/119/1/hr/BILLS-119hr22ih.xml"

    assert is_nil(version("eh").text_source_id)

    assert [%{args: %{"bill_external_id" => "119-hr-22", "code" => "eh"}}] =
             all_enqueued(worker: SyncBillText)

    run = Provenance.last_succeeded_run("federal", "backfill_bill_text")
    assert run.stats["stored"] == 1
    assert run.stats["fallback"] == 1
  end

  test "HTML or unparseable entries are skipped and fall back" do
    stub(
      zip([
        {"BILLS-119hr22ih.xml", "<!DOCTYPE html><html>error</html>"},
        {"BILLS-119hr22eh.xml", "<bill><unclosed>"}
      ])
    )

    assert :ok = perform_job(BackfillBillText, %{"congress" => 119})

    assert is_nil(version("ih").text_source_id)
    assert is_nil(version("eh").text_source_id)
    assert length(all_enqueued(worker: SyncBillText)) == 2
  end
end
