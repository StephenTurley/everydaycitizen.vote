defmodule EverydayCitizen.Adapters.Federal.Normalize.BillStatusTest do
  use ExUnit.Case, async: true

  alias EverydayCitizen.Adapters.Federal.Normalize.Bill
  alias EverydayCitizen.Adapters.Federal.Normalize.BillStatus
  alias EverydayCitizen.Ingest.Records.SourceRef

  @api "test/support/fixtures/federal/congress_gov/bill_119_hr_22"
  @bulk "test/support/fixtures/federal/govinfo/BILLSTATUS-119hr22.xml"
  @src SourceRef.new("https://x.test/a", "a", ~U[2026-10-23 00:00:00Z])

  defp api(file), do: "#{@api}/#{file}.json" |> File.read!() |> Jason.decode!()

  defp bulk do
    {:ok, parts} = @bulk |> File.read!() |> BillStatus.parse()
    parts
  end

  test "bulk and API produce the same bill and actions for 119 hr 22" do
    b = bulk()

    assert Bill.bill(b.detail, b.subjects, @src) == Bill.bill(api("bill"), api("subjects"), @src)

    assert Bill.actions(b.actions, "119-hr-22", @src) ==
             Bill.actions(api("actions")["actions"], "119-hr-22", @src)
  end

  test "bulk sponsorships hold every cosponsor, matching the API's first page" do
    b = bulk()
    from_bulk = Bill.sponsorships(b.detail, b.cosponsors, "119-hr-22", @src).sponsorships
    from_api = Bill.sponsorships(api("bill"), api("cosponsors")["cosponsors"], "119-hr-22", @src)

    # The API fixture is the first page of cosponsors (5 of 110); the bulk file has all.
    assert length(from_bulk) == 111
    assert Enum.all?(from_api.sponsorships, &(&1 in from_bulk))
  end

  test "bulk text versions match the API's except for the (GovInfo) urls" do
    b = bulk()
    drop_urls = fn versions -> Enum.map(versions, &%{&1 | xml_url: nil, text_url: nil}) end
    from_bulk = Bill.versions(b.text["textVersions"], "119-hr-22", @src)

    assert drop_urls.(from_bulk) ==
             drop_urls.(Bill.versions(api("text")["textVersions"], "119-hr-22", @src))

    assert Enum.map(from_bulk, & &1.xml_url) == [
             "https://www.govinfo.gov/content/pkg/BILLS-119hr22eh/xml/BILLS-119hr22eh.xml",
             "https://www.govinfo.gov/content/pkg/BILLS-119hr22ih/xml/BILLS-119hr22ih.xml"
           ]
  end

  test "empty list elements become empty lists" do
    xml = """
    <billStatus><bill><number>9</number><type>HR</type><congress>119</congress>
    <title>T</title><actions/><cosponsors></cosponsors><textVersions/></bill></billStatus>
    """

    assert {:ok, %{actions: [], cosponsors: [], text: %{"textVersions" => []}} = parts} =
             BillStatus.parse(xml)

    assert parts.detail["bill"]["number"] == "9"
  end

  test "a bill with no legislative subjects normalizes to no subjects" do
    xml = """
    <billStatus><bill><number>9</number><type>HR</type><congress>119</congress>
    <title>T</title><subjects><legislativeSubjects/></subjects></bill></billStatus>
    """

    assert {:ok, parts} = BillStatus.parse(xml)
    assert Bill.bill(parts.detail, parts.subjects, @src).subjects == []
  end

  test "repeated non-item children become a list; a single one stays a map" do
    xml = """
    <billStatus><bill><number>9</number><type>HR</type><congress>119</congress><title>T</title>
    <summaries><summary><versionCode>00</versionCode></summary><summary><versionCode>36</versionCode></summary></summaries>
    <policyArea><name>Taxation</name></policyArea></bill></billStatus>
    """

    assert {:ok, parts} = BillStatus.parse(xml)

    assert parts.detail["bill"]["summaries"]["summary"] == [
             %{"versionCode" => "00"},
             %{"versionCode" => "36"}
           ]

    assert parts.detail["bill"]["policyArea"] == %{"name" => "Taxation"}
    assert Enum.map(parts.summaries, & &1["versionCode"]) == ["00", "36"]
  end

  test "every summary in the hr22 file is kept" do
    assert length(bulk().summaries) == 1
  end

  test "summaries normalize to the bill's summary set, sanitized and attributed" do
    b = bulk()
    record = Bill.summaries(b.summaries, "119-hr-22", @src)

    assert record.author == "Congressional Research Service"
    assert [%{version_code: "00", action_date: ~D[2025-01-03], html: html}] = record.summaries
    assert html =~ "<strong>"
  end

  test "a bill without summaries has none" do
    assert {:ok, %{summaries: []}} =
             BillStatus.parse(
               "<billStatus><bill><number>9</number><type>HR</type></bill></billStatus>"
             )
  end

  test "malformed XML returns an error" do
    xml = File.read!("test/support/fixtures/federal/govinfo/malformed.xml")
    assert {:error, _} = BillStatus.parse(xml)
  end

  test "a document without a bill element returns an error" do
    assert {:error, :no_bill} = BillStatus.parse("<billStatus><version>3</version></billStatus>")
  end
end
