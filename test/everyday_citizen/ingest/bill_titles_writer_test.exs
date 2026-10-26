defmodule EverydayCitizen.Ingest.BillTitlesWriterTest do
  use EverydayCitizen.DataCase, async: true
  import Ecto.Query

  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Legislation.BillTitle
  alias EverydayCitizen.Repo

  setup do
    for record <- [
          %Records.Jurisdiction{
            key: "fed",
            name: "Fed",
            classification: "federal",
            time_zone: "America/New_York",
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
            external_id: "119-hr-1",
            identifier: "HR 1",
            classification: "bill",
            title: "A bill",
            subjects: [],
            introduced_on: ~D[2026-01-03],
            source: source_ref()
          }
        ],
        do: {:ok, _} = Ingest.write(record, nil)

    :ok
  end

  defp write_titles(titles) do
    {:ok, _} =
      Ingest.write(
        %Records.BillTitles{
          jurisdiction: "fed",
          bill_external_id: "119-hr-1",
          titles: titles,
          source: source_ref()
        },
        nil
      )
  end

  defp stored, do: Repo.all(from t in BillTitle, order_by: t.title, select: t.title)

  test "writing BillTitles replaces the bill's set" do
    write_titles([%{title: "a", kind: "short"}, %{title: "b", kind: "official"}])
    assert stored() == ["a", "b"]

    write_titles([%{title: "b", kind: "official"}])
    assert stored() == ["b"]
  end

  test "ec_name_key normalizes names" do
    for {input, key} <- [
          {"SAVE Act", "save"},
          {"Laken Riley Act of 2025", "laken riley"},
          {"One Big Beautiful Bill Act", "one big beautiful bill"},
          {"  H.R. 22 — the SAVE act!", "h r 22 the save"}
        ] do
      assert Repo.query!("select ec_name_key($1)", [input]).rows == [[key]]
    end
  end
end
