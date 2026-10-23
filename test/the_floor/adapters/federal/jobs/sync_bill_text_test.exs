defmodule TheFloor.Adapters.Federal.Jobs.SyncBillTextTest do
  use TheFloor.DataCase, async: true
  use Oban.Testing, repo: TheFloor.Repo

  alias TheFloor.Adapters.Federal.Jobs.SyncBillText
  alias TheFloor.Ingest
  alias TheFloor.Ingest.Records
  alias TheFloor.Legislation
  alias TheFloor.Legislation.BillVersion
  alias TheFloor.Repo

  @dir "test/support/fixtures/federal/govinfo"
  @govinfo "/content/pkg/BILLS-119hr22ih/xml/BILLS-119hr22ih.xml"
  @args %{"bill_external_id" => "119-hr-22", "code" => "ih"}

  setup do
    write!(%Records.Jurisdiction{
      key: "federal",
      name: "Federal",
      classification: "federal",
      source: src()
    })

    write!(%Records.LegislativeSession{jurisdiction: "federal", identifier: "119", source: src()})

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

    write!(%Records.BillVersion{
      jurisdiction: "federal",
      bill_external_id: "119-hr-22",
      code: "ih",
      xml_url: "https://www.congress.gov/119/bills/hr22/BILLS-119hr22ih.xml",
      source: src()
    })

    :ok
  end

  defp src, do: Records.SourceRef.new("https://x.test/a", "a")

  defp write!(record) do
    {:ok, row} = Ingest.write(record, nil)
    row
  end

  defp version, do: Repo.one!(BillVersion)

  defp stub(routes) do
    Req.Test.stub(TheFloor.Federal, fn conn ->
      case Map.get(routes, conn.host <> conn.request_path) || Map.get(routes, conn.request_path) do
        nil -> Plug.Conn.send_resp(conn, 404, "nope")
        {status, body} -> Plug.Conn.send_resp(conn, status, body)
      end
    end)
  end

  test "stores xml and plain text from GovInfo" do
    stub(%{@govinfo => {200, File.read!("#{@dir}/BILLS-119hr22ih.xml")}})
    assert :ok = perform_job(SyncBillText, @args)

    v = version()
    assert v.xml_schema == "other"
    assert v.plain_text =~ "Short title\n"
    assert v.xml =~ "<legis-body"
    assert v.text_source_id
    assert Legislation.versions_missing_text(10) == []
  end

  test "marks USLM documents as uslm" do
    stub(%{@govinfo => {200, File.read!("#{@dir}/uslm_sample.xml")}})
    assert :ok = perform_job(SyncBillText, @args)
    assert version().xml_schema == "uslm"
  end

  test "falls back to the version's xml_url on 404" do
    stub(%{
      "www.congress.gov/119/bills/hr22/BILLS-119hr22ih.xml" =>
        {200, File.read!("#{@dir}/BILLS-119hr22ih.xml")}
    })

    assert :ok = perform_job(SyncBillText, @args)
    assert version().plain_text =~ "Short title"
    assert version().xml_schema == "other"
  end

  @tag :capture_log
  test "missing everywhere leaves text nil and returns :ok" do
    stub(%{})
    assert :ok = perform_job(SyncBillText, @args)
    assert version().text_source_id == nil
    assert [_] = Legislation.versions_missing_text(10)
  end

  @html "<!DOCTYPE html>\n<html lang=\"en\"><head><title>Error</title></head><body><p>Not found</p></body></html>"

  test "an HTML 200 from GovInfo falls through to xml_url" do
    stub(%{
      @govinfo => {200, @html},
      "www.congress.gov/119/bills/hr22/BILLS-119hr22ih.xml" =>
        {200, File.read!("#{@dir}/BILLS-119hr22ih.xml")}
    })

    assert :ok = perform_job(SyncBillText, @args)
    assert version().plain_text =~ "Short title"
    refute version().xml =~ "<html"
  end

  @tag :capture_log
  test "HTML 200 on both URLs leaves text nil and returns :ok" do
    stub(%{
      @govinfo => {200, @html},
      "www.congress.gov/119/bills/hr22/BILLS-119hr22ih.xml" => {200, @html}
    })

    assert :ok = perform_job(SyncBillText, @args)
    assert version().text_source_id == nil
    assert version().plain_text == nil
  end

  @tag :capture_log
  test "malformed xml leaves text nil and returns :ok" do
    stub(%{@govinfo => {200, File.read!("#{@dir}/malformed.xml")}})
    assert :ok = perform_job(SyncBillText, @args)
    assert version().text_source_id == nil
    assert version().xml == nil
  end

  @tag :capture_log
  test "server errors are returned so Oban retries" do
    stub(%{@govinfo => {503, "down"}})
    assert {:error, _} = perform_job(SyncBillText, @args)
  end
end
