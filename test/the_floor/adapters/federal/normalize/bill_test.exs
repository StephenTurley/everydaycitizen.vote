defmodule TheFloor.Adapters.Federal.Normalize.BillTest do
  use ExUnit.Case, async: true

  alias TheFloor.Adapters.Federal.Normalize.Bill, as: Normalize
  alias TheFloor.Ingest.Records
  alias TheFloor.Ingest.Records.SourceRef

  @dir "test/support/fixtures/federal/congress_gov/bill_119_hr_22"

  defp load(name), do: @dir |> Path.join(name) |> File.read!() |> JSON.decode!()
  defp src(name), do: SourceRef.new("https://example.test/#{name}", name)

  describe "bill/3" do
    test "builds ids, identifier, classification, dates and subjects" do
      bill = Normalize.bill(load("bill.json"), load("subjects.json"), src("bill"))

      assert %Records.Bill{
               jurisdiction: "federal",
               session_identifier: "119",
               external_id: "119-hr-22",
               identifier: "H.R. 22",
               classification: "bill",
               title: "SAVE Act",
               from_body_external_id: "house",
               introduced_on: ~D[2025-01-03]
             } = bill

      assert bill.updated_at_source == ~U[2026-08-10 14:13:39Z]
      # the fixture's count of 12 also includes the policy area
      assert length(bill.subjects) == 11
      assert "Citizenship and naturalization" in bill.subjects
      assert bill.source.url == "https://example.test/bill"
    end

    test "HJRES 5 maps to 119-hjres-5 / H.J.Res. 5" do
      json = %{
        "bill" => %{
          "congress" => 119,
          "type" => "HJRES",
          "number" => "5",
          "title" => "T",
          "originChamberCode" => "H"
        }
      }

      bill = Normalize.bill(json, %{}, src("b"))
      assert bill.external_id == "119-hjres-5"
      assert bill.identifier == "H.J.Res. 5"
      assert bill.classification == "joint_resolution"
      assert bill.subjects == []
      assert bill.introduced_on == nil
    end
  end

  describe "actions/3" do
    test "are chronological, 0-based, classified, with chamber actors" do
      %Records.BillActions{actions: actions, bill_external_id: "119-hr-22"} =
        Normalize.actions(load("actions.json")["actions"], "119-hr-22", src("actions"))

      assert length(actions) == 19
      assert Enum.map(actions, & &1.position) == Enum.to_list(0..18)
      assert Enum.map(actions, & &1.date) == Enum.sort(Enum.map(actions, & &1.date), Date)

      [first, second | _] = actions
      assert first.description == "Introduced in House"
      assert first.classification == "introduced"
      assert first.actor_body_external_id == nil
      assert second.classification == "introduced"

      referral = Enum.find(actions, &(&1.description =~ "Referred to the House Committee"))
      assert referral.classification == "referred"
      assert referral.actor_body_external_id == "house"
      assert referral.raw_type == "IntroReferral"

      last = List.last(actions)
      assert last.description == "Received in the Senate."
      assert last.actor_body_external_id == "senate"

      assert Enum.any?(actions, &(&1.classification == "passed_chamber"))
      assert Enum.any?(actions, &is_nil(&1.classification))
      assert Enum.all?(actions, &(&1.actor_body_external_id in [nil, "house", "senate"]))
    end
  end

  describe "sponsorships/4" do
    test "sponsor is primary, cosponsors keep dates" do
      %Records.Sponsorships{sponsorships: list} =
        Normalize.sponsorships(
          load("bill.json"),
          load("cosponsors.json")["cosponsors"],
          "119-hr-22",
          src("cosponsors")
        )

      assert [primary | cosponsors] = list

      assert primary == %{
               person: {"bioguide", "R000614"},
               classification: "primary",
               date: ~D[2025-01-03],
               withdrawn_on: nil
             }

      assert length(cosponsors) == 5
      assert Enum.all?(cosponsors, &(&1.classification == "cosponsor" and &1.withdrawn_on == nil))
      assert hd(cosponsors).person == {"bioguide", "G000597"}
      assert hd(cosponsors).date == ~D[2025-01-03]
    end

    test "SYNTHETIC: a cosponsor with sponsorshipWithdrawnDate has withdrawn_on" do
      [first | rest] = load("cosponsors.json")["cosponsors"]
      edited = [Map.put(first, "sponsorshipWithdrawnDate", "2025-02-01") | rest]

      %Records.Sponsorships{sponsorships: [_primary, withdrawn | others]} =
        Normalize.sponsorships(load("bill.json"), edited, "119-hr-22", src("c"))

      assert withdrawn.withdrawn_on == ~D[2025-02-01]
      assert Enum.all?(others, &is_nil(&1.withdrawn_on))
    end
  end

  describe "versions/3" do
    test "codes come from the package suffix; urls from formats" do
      versions = Normalize.versions(load("text.json")["textVersions"], "119-hr-22", src("text"))

      assert [%Records.BillVersion{} = eh, %Records.BillVersion{} = ih] = versions
      assert {eh.code, ih.code} == {"eh", "ih"}
      assert eh.classification == "Engrossed in House"
      assert eh.date == ~D[2025-04-10]
      assert eh.xml_url == "https://www.congress.gov/119/bills/hr22/BILLS-119hr22eh.xml"
      assert eh.text_url == "https://www.congress.gov/119/bills/hr22/BILLS-119hr22eh.htm"
      assert eh.bill_external_id == "119-hr-22"
    end

    test "a version with no recognizable package url is dropped" do
      assert [] =
               Normalize.versions(
                 [%{"type" => "X", "date" => nil, "formats" => []}],
                 "119-hr-22",
                 src("t")
               )
    end
  end
end
