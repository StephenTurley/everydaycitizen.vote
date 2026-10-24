defmodule EverydayCitizen.Adapters.Federal.Normalize.BillContextTest do
  use ExUnit.Case, async: true

  alias EverydayCitizen.Adapters.Federal.Normalize.BillContext
  alias EverydayCitizen.Ingest.Records.{BillAmendments, BillCommittees, BillRelations, SourceRef}

  @dir "test/support/fixtures/federal/congress_gov/bill_119_hr_7008"
  defp json(name), do: "#{@dir}/#{name}.json" |> File.read!() |> Jason.decode!()
  defp src, do: SourceRef.new("https://example.test/x", "x")

  test "committee activities name the committee by code and the step by kind" do
    %BillCommittees{bill_external_id: "119-hr-7008", activities: acts} =
      BillContext.committees(json("committees")["committees"], "119-hr-7008", src())

    assert %{body_external_id: "hsha00", kind: "referred", date: ~D[2026-01-12]} in acts
    assert %{body_external_id: "hsha00", kind: "markup", date: ~D[2026-01-14]} in acts
    assert %{body_external_id: "hsha00", kind: "reported", date: ~D[2026-02-03]} in acts
    assert Enum.count(acts, &(&1.kind == "other")) == 2
  end

  test "related measures: procedurally related ones are procedural" do
    %BillRelations{relations: rels} =
      BillContext.relations(json("relatedbills")["relatedBills"], "119-hr-7008", src())

    assert %{bill_external_id: "119-hres-1438", kind: "procedural"} in rels
    assert %{bill_external_id: "119-s-4134", kind: "related"} in rels
  end

  test "amendments keep their official description, latest action and page" do
    %BillAmendments{amendments: [amdt]} =
      BillContext.amendments(json("amendments")["amendments"], %{}, "119-hr-7008", src())

    assert amdt.external_id == "119-hamdt-267"
    assert amdt.identifier == "H.Amdt. 267"
    assert amdt.description =~ "is considered adopted"
    assert amdt.latest_action =~ "Agreed to without objection"
    assert amdt.latest_action_date == ~D[2026-07-22]
    assert amdt.url == "https://www.congress.gov/amendment/119th-congress/house-amendment/267"
  end

  test "a detail is wanted only for an agreed amendment without a description" do
    agreed = %{"latestAction" => %{"text" => "Amendment SA 1 agreed to in Senate by Voice Vote."}}
    refute BillContext.needs_detail?(Map.put(agreed, "description", "Has one."))
    assert BillContext.needs_detail?(agreed)
    refute BillContext.needs_detail?(%{"latestAction" => %{"text" => "Submitted in the Senate."}})
  end

  test "a fetched detail supplies a Senate amendment's purpose" do
    item = %{
      "congress" => 119,
      "type" => "SAMDT",
      "number" => "6835",
      "latestAction" => %{"actionDate" => "2026-09-28", "text" => "agreed to in Senate"}
    }

    %BillAmendments{amendments: [a]} =
      BillContext.amendments(
        [item],
        %{"6835" => %{"purpose" => "To improve the bill."}},
        "119-s-4668",
        src()
      )

    assert a.identifier == "S.Amdt. 6835"
    assert a.description == "To improve the bill."
    assert a.url == "https://www.congress.gov/amendment/119th-congress/senate-amendment/6835"
  end
end
