defmodule TheFloor.Adapters.Federal.BulkTest do
  use ExUnit.Case, async: true

  alias TheFloor.Adapters.Federal.Bulk
  alias TheFloor.Ingest.Records.SourceRef

  @url "https://www.govinfo.gov/bulkdata/BILLSTATUS/119/dir/all.zip"

  defp zip_bytes do
    {:ok, {_name, bytes}} =
      :zip.create(
        ~c"t.zip",
        [{~c"A.xml", "<a/>"}, {~c"B.xml", "<b/>"}, {~c"readme.txt", "x"}],
        [:memory]
      )

    bytes
  end

  defp stub(status, body) do
    Req.Test.stub(TheFloor.Federal, fn conn -> Plug.Conn.send_resp(conn, status, body) end)
  end

  test "reduce_entries visits each xml entry with a per-file source" do
    stub(200, zip_bytes())

    assert {:ok, entries} =
             Bulk.with_zip(@url, fn zip ->
               zip |> Bulk.reduce_entries([], &[&1 | &2]) |> Enum.reverse()
             end)

    assert [{"A.xml", "<a/>", %SourceRef{} = a}, {"B.xml", "<b/>", b}] = entries
    assert a.url == "https://www.govinfo.gov/bulkdata/BILLSTATUS/119/dir/A.xml"
    assert b.url == "https://www.govinfo.gov/bulkdata/BILLSTATUS/119/dir/B.xml"
    assert a.content_hash == SourceRef.new(a.url, "<a/>").content_hash
    assert %DateTime{} = a.fetched_at
  end

  test "with_zip deletes the temp file even when fun raises" do
    stub(200, zip_bytes())
    parent = self()

    assert_raise RuntimeError, fn ->
      Bulk.with_zip(@url, fn zip ->
        send(parent, {:path, zip.path})
        raise "boom"
      end)
    end

    assert_received {:path, path}
    refute File.exists?(path)
  end

  test "with_zip returns {:error, :not_a_zip} for an HTML 200" do
    stub(200, "<!DOCTYPE html><html>missing</html>")
    assert {:error, :not_a_zip} = Bulk.with_zip(@url, fn _ -> flunk("called") end)
  end

  test "with_zip passes through HTTP errors" do
    stub(404, "nope")
    assert {:error, {:http_status, 404}} = Bulk.with_zip(@url, fn _ -> flunk("called") end)
  end
end
