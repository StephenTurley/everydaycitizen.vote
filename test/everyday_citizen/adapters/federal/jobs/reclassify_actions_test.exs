defmodule EverydayCitizen.Adapters.Federal.Jobs.ReclassifyActionsTest do
  use EverydayCitizen.DataCase, async: true
  use Oban.Testing, repo: EverydayCitizen.Repo

  alias EverydayCitizen.Adapters.Federal.Jobs.ReclassifyActions
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Legislation.BillAction

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
            external_id: "119-s-1",
            identifier: "S. 1",
            classification: "bill",
            title: "T",
            source: src
          },
          %Records.BillActions{
            jurisdiction: "federal",
            bill_external_id: "119-s-1",
            actions: [
              %Records.BillAction{
                position: 0,
                description:
                  "Motion to proceed to consideration of measure agreed to in Senate by Yea-Nay Vote. 77 - 22.",
                classification: "passed_chamber"
              },
              %Records.BillAction{
                position: 1,
                description: "Introduced in Senate",
                classification: "introduced"
              }
            ],
            source: src
          }
        ] do
      {:ok, _} = Ingest.write(r, nil)
    end

    :ok
  end

  test "stored actions are classified again with the current rules" do
    assert :ok = perform_job(ReclassifyActions, %{})

    assert [motion, intro] = Repo.all(from a in BillAction, order_by: a.position)
    assert {motion.classification, motion.unclassified} == {nil, true}
    assert intro.classification == "introduced"
  end

  test "it runs by name and is not part of the full ingest" do
    assert {:ok, [{"reclassify_actions", ReclassifyActions, _}]} =
             EverydayCitizen.Ingest.Jobs.select("reclassify_actions")

    refute Enum.any?(EverydayCitizen.Ingest.Jobs.all(), &(elem(&1, 0) == "reclassify_actions"))
  end
end
