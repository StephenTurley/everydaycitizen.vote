defmodule EverydayCitizen.Search.ExcerptTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Legislation
  alias EverydayCitizen.Search.Excerpt

  import EverydayCitizen.HistoryFixtures, only: [section: 3]

  setup do
    for record <- [
          %Records.Jurisdiction{
            key: "fed",
            name: "Fed",
            classification: "federal",
            source: source_ref()
          },
          %Records.LegislativeSession{
            jurisdiction: "fed",
            identifier: "119",
            source: source_ref()
          },
          %Records.Bill{
            jurisdiction: "fed",
            session_identifier: "119",
            external_id: "119-hr-100",
            identifier: "H.R. 100",
            classification: "bill",
            title: "Sunshine Protection Act",
            subjects: [],
            introduced_on: ~D[2026-01-03],
            source: source_ref()
          }
        ],
        do: {:ok, _} = Ingest.write(record, nil)

    %{bill: Legislation.get_bill("fed", "119-hr-100")}
  end

  defp version!(bill, code, plain_text, sections) do
    {:ok, _} =
      Ingest.write(
        %Records.BillVersion{
          jurisdiction: "fed",
          bill_external_id: bill.external_id,
          code: code,
          source: source_ref()
        },
        nil
      )

    {:ok, _} =
      Ingest.write(
        %Records.BillVersionText{
          jurisdiction: "fed",
          bill_external_id: bill.external_id,
          code: code,
          xml: "<bill/>",
          xml_schema: "other",
          plain_text: plain_text,
          sections: sections,
          sections_version: 2,
          source: source_ref()
        },
        nil
      )

    Legislation.get_version(bill, code)
  end

  defp block(text), do: %{"enum" => nil, "text" => text, "level" => 0, "heading" => nil}

  test "an excerpt names the section and marks the match", %{bill: bill} do
    version =
      version!(bill, "ih", "whole text", [
        section("1.", "Short title", [block("This Act may be cited as the Sunshine Act.")]),
        section("4.", "Clocks", [
          block("Clocks are set by the Secretary."),
          block("Daylight saving time shall be permanent.")
        ])
      ])

    assert %{section: "Sec. 4 Clocks", parts: parts} =
             Excerpt.build(version.id, "daylight saving time")

    assert {:mark, "Daylight"} in parts
    assert Enum.map_join(parts, &elem(&1, 1)) =~ "shall be permanent"
  end

  test "a section without a heading is labeled by its number alone", %{bill: bill} do
    version = version!(bill, "ih", "whole text", [section("7", nil, [block("Daylight rules.")])])
    assert %{section: "Sec. 7"} = Excerpt.build(version.id, "daylight")
  end

  test "bill text markup comes out as text, not HTML", %{bill: bill} do
    version =
      version!(bill, "ih", "whole text", [
        section("1.", "Rules", [block("Section <script>alert(1)</script> & daylight rules")])
      ])

    %{parts: parts} = Excerpt.build(version.id, "daylight")

    assert Enum.any?(parts, fn
             {:text, t} -> t =~ "<script>"
             _ -> false
           end)
  end

  test "a version without sections still gets an excerpt with no section label", %{bill: bill} do
    plain_only = version!(bill, "ih", "Clocks. Daylight saving time is permanent.", nil)
    assert %{section: nil, parts: [_ | _] = parts} = Excerpt.build(plain_only.id, "daylight")
    assert {:mark, "Daylight"} in parts
  end

  test "sections that never match fall back to the whole text", %{bill: bill} do
    version =
      version!(bill, "ih", "Title. Daylight saving time.", [
        section("1.", "Short title", [block("Nothing here.")])
      ])

    assert %{section: nil, parts: parts} = Excerpt.build(version.id, "daylight")
    assert {:mark, "Daylight"} in parts
  end
end
