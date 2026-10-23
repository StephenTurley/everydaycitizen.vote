defmodule TheFloor.Adapters.Federal.Jobs.SyncBillText do
  @moduledoc """
  Fetches the XML of one bill version from GovInfo (falling back to the version's
  own `xml_url`), extracts plain text and stores both. A version with no XML or
  unparseable XML keeps nil text and the job succeeds; other failures are returned
  so Oban retries.
  """
  use Oban.Worker, queue: :text, max_attempts: 5

  require Logger

  alias TheFloor.Adapters.Federal.{HTTP, XmlText}
  alias TheFloor.Ingest
  alias TheFloor.Ingest.Records.BillVersionText
  alias TheFloor.Legislation

  @govinfo "https://www.govinfo.gov/content/pkg"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"bill_external_id" => bill_id, "code" => code}}) do
    with %{} = bill <- Legislation.get_bill("federal", bill_id),
         %{} = version <- Legislation.get_version(bill, code) do
      fetch_first(urls(bill_id, code, version), bill_id, code)
    else
      nil ->
        Logger.warning("sync_bill_text: no version #{bill_id}/#{code}")
        :ok
    end
  end

  defp fetch_first([], bill_id, code) do
    Logger.warning("sync_bill_text: no usable XML found for #{bill_id}/#{code}")
    :ok
  end

  defp fetch_first([url | rest], bill_id, code) do
    case HTTP.get(url, limiter: :govinfo, decode: :raw) do
      {:ok, %{raw: raw, source: source}} ->
        with false <- html?(raw),
             {:ok, text} <- XmlText.plain_text(raw) do
          store(raw, text, source, bill_id, code)
        else
          _not_xml -> fetch_first(rest, bill_id, code)
        end

      {:error, {:http_status, 404}} ->
        fetch_first(rest, bill_id, code)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # GovInfo signals a missing file with HTTP 200 and an HTML page.
  defp html?(raw) do
    head =
      raw
      |> binary_part(0, min(byte_size(raw), 512))
      |> String.trim_leading()
      |> String.downcase()

    String.starts_with?(head, ["<!doctype html", "<html"])
  end

  defp store(xml, text, source, bill_id, code) do
    {:ok, _} =
      Ingest.write(
        %BillVersionText{
          jurisdiction: "federal",
          bill_external_id: bill_id,
          code: code,
          xml: xml,
          xml_schema: XmlText.schema(xml),
          plain_text: text,
          source: source
        },
        nil
      )

    :ok
  end

  # GovInfo serves 119th-Congress bill XML under /xml/ (the /uslm/ path answers 200 with an
  # HTML error page), so the package XML is tried first, then the version's own xml_url.
  defp urls(bill_id, code, version) do
    [package_url(bill_id, code), version.xml_url] |> Enum.reject(&is_nil/1) |> Enum.uniq()
  end

  defp package_url(bill_id, code) do
    [congress, type, number] = String.split(bill_id, "-")
    pkg = "BILLS-#{congress}#{type}#{number}#{code}"
    "#{@govinfo}/#{pkg}/xml/#{pkg}.xml"
  end
end
