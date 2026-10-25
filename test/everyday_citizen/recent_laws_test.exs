defmodule EverydayCitizen.RecentLawsTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Legislation

  @src Records.SourceRef.new("https://x.test/laws", "l")

  setup do
    EverydayCitizen.FloorFixtures.iowa!()

    # {external id, [{position, date, classification}]}
    for {id, actions} <- [
          {"119-hr-1", [{0, ~D[2026-03-01], "introduced"}, {1, ~D[2026-09-01], "became_law"}]},
          {"119-hr-2", [{0, ~D[2026-03-01], "became_law"}, {1, ~D[2026-10-20], "became_law"}]},
          {"119-hr-3", [{0, ~D[2026-03-01], "introduced"}, {1, ~D[2026-10-20], "became_law"}]},
          {"119-hr-4", [{0, ~D[2026-03-01], "introduced"}, {1, ~D[2026-10-22], "signed"}]}
        ] do
      {:ok, _} =
        Ingest.write(
          %Records.Bill{
            jurisdiction: "federal",
            session_identifier: "119",
            external_id: id,
            identifier: id,
            classification: "bill",
            title: "Bill #{id}",
            source: @src
          },
          nil
        )

      {:ok, _} =
        Ingest.write(
          %Records.BillActions{
            jurisdiction: "federal",
            bill_external_id: id,
            actions:
              for {pos, date, class} <- actions do
                %Records.BillAction{
                  position: pos,
                  date: date,
                  description: class,
                  classification: class
                }
              end,
            source: @src
          },
          nil
        )
    end

    :ok
  end

  defp ids(laws), do: Enum.map(laws, &{&1.bill.external_id, &1.date})

  test "newest first by the latest became-law action, each bill once, ties by newest bill" do
    assert ids(Legislation.recent_laws(5, 0)) == [
             {"119-hr-3", ~D[2026-10-20]},
             {"119-hr-2", ~D[2026-10-20]},
             {"119-hr-1", ~D[2026-09-01]}
           ]
  end

  test "limit and offset page through them" do
    assert ids(Legislation.recent_laws(2, 0)) == [
             {"119-hr-3", ~D[2026-10-20]},
             {"119-hr-2", ~D[2026-10-20]}
           ]

    assert ids(Legislation.recent_laws(2, 2)) == [{"119-hr-1", ~D[2026-09-01]}]
    assert Legislation.recent_laws(2, 4) == []
  end
end
