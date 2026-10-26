defmodule EverydayCitizen.Ingest.Writer.LegislationTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Legislation
  alias EverydayCitizen.Legislation.{Bill, BillAction, BillVersion, Sponsorship}

  @jur "fed"

  setup do
    write!(%Records.Jurisdiction{
      key: @jur,
      name: "Fed",
      classification: "federal",
      time_zone: "America/New_York",
      source: source_ref()
    })

    write!(%Records.LegislativeSession{
      jurisdiction: @jur,
      identifier: "119",
      source: source_ref()
    })

    write!(%Records.Body{
      jurisdiction: @jur,
      external_id: "lower",
      name: "Lower",
      classification: "chamber",
      source: source_ref()
    })

    write!(%Records.Person{identifiers: [{"id", "P1"}], name: "Pat", source: source_ref()})
    write!(%Records.Person{identifiers: [{"id", "P2"}], name: "Sam", source: source_ref()})
    :ok
  end

  defp write!(record) do
    {:ok, row} = Ingest.write(record, nil)
    row
  end

  defp bill(attrs \\ []) do
    struct!(
      %Records.Bill{
        jurisdiction: @jur,
        session_identifier: "119",
        external_id: "119-hr-1",
        identifier: "HR 1",
        classification: "bill",
        title: "A bill",
        subjects: ["Taxes"],
        from_body_external_id: "lower",
        introduced_on: ~D[2026-01-03],
        source: source_ref()
      },
      attrs
    )
  end

  defp action(position, attrs \\ []) do
    struct!(
      %Records.BillAction{
        position: position,
        date: ~D[2026-01-04],
        description: "Action #{position}",
        classification: "introduced"
      },
      attrs
    )
  end

  defp actions(list, bill_id \\ "119-hr-1") do
    %Records.BillActions{
      jurisdiction: @jur,
      bill_external_id: bill_id,
      actions: list,
      source: source_ref()
    }
  end

  defp sponsorships(list) do
    %Records.Sponsorships{
      jurisdiction: @jur,
      bill_external_id: "119-hr-1",
      sponsorships: list,
      source: source_ref()
    }
  end

  defp count(schema), do: Repo.aggregate(schema, :count)

  test "writes a bill and finds it by jurisdiction and external id" do
    write!(bill())
    b = Legislation.get_bill(@jur, "119-hr-1")
    assert %Bill{title: "A bill", subjects: ["Taxes"], classification: "bill"} = b
    assert Legislation.count_bills(b.session_id) == 1
  end

  test "bill referencing unknown session returns an error" do
    assert {:error, {:unknown_session, "x"}} = Ingest.write(bill(session_identifier: "x"), nil)
    assert count(Bill) == 0
  end

  test "rejects an unknown classification" do
    assert {:error, %Ecto.Changeset{}} = Ingest.write(bill(classification: "nope"), nil)
  end

  test "replaces the action set on re-ingest" do
    write!(bill())
    write!(actions([action(1), action(2), action(3)]))
    assert count(BillAction) == 3

    write!(actions([action(1), action(2, description: "Edited")]))

    rows = BillAction |> order_by(:position) |> Repo.all()
    assert Enum.map(rows, & &1.position) == [1, 2]
    assert Enum.map(rows, & &1.description) == ["Action 1", "Edited"]
  end

  test "action with nil classification is flagged unclassified" do
    write!(bill())
    write!(actions([action(1), action(2, classification: nil, raw_type: "Weird")]))

    assert [%BillAction{position: 2, unclassified: true, raw_type: "Weird"}] =
             Repo.all(where(BillAction, [a], a.unclassified))
  end

  # Congress.gov and BILLSTATUS both carry some Library of Congress actions with
  # only a date and code (e.g. "Intro-S"); they are kept as the source has them.
  test "an action without a description is stored" do
    write!(bill())
    write!(actions([action(1), action(2, description: nil, raw_code: "Intro-S")]))

    assert %BillAction{description: nil, raw_code: "Intro-S"} =
             Repo.get_by!(BillAction, position: 2)
  end

  test "action with an unknown actor body returns an error and writes nothing" do
    write!(bill())

    assert {:error, {:unknown_body, "nope"}} =
             Ingest.write(actions([action(1, actor_body_external_id: "nope")]), nil)

    assert count(BillAction) == 0
  end

  test "actions for an unknown bill return an error" do
    assert {:error, {:unknown_bill, "zzz"}} = Ingest.write(actions([action(1)], "zzz"), nil)
  end

  test "sponsorships skip unknown people and report them" do
    write!(bill())

    assert {:ok, %{written: 2, skipped_people: [{"id", "NOPE"}]}} =
             Ingest.write(
               sponsorships([
                 %{person: {"id", "P1"}, classification: "primary", date: ~D[2026-01-03]},
                 %{person: {"id", "P2"}, classification: "cosponsor", date: ~D[2026-01-05]},
                 %{person: {"id", "NOPE"}, classification: "cosponsor", date: nil}
               ]),
               nil
             )

    assert count(Sponsorship) == 2
  end

  test "sponsorships replace the set, including withdrawal" do
    write!(bill())

    write!(
      sponsorships([
        %{person: {"id", "P1"}, classification: "primary"},
        %{person: {"id", "P2"}, classification: "cosponsor"}
      ])
    )

    write!(
      sponsorships([
        %{person: {"id", "P1"}, classification: "primary"}
      ])
    )

    assert [%Sponsorship{classification: "primary"}] = Repo.all(Sponsorship)

    write!(
      sponsorships([
        %{person: {"id", "P1"}, classification: "primary", withdrawn_on: ~D[2026-02-01]}
      ])
    )

    assert [%Sponsorship{withdrawn_on: ~D[2026-02-01]}] = Repo.all(Sponsorship)
  end

  test "BillVersionText updates text without touching date/urls" do
    write!(bill())

    write!(%Records.BillVersion{
      jurisdiction: @jur,
      bill_external_id: "119-hr-1",
      code: "ih",
      classification: "introduced",
      date: ~D[2026-01-03],
      xml_url: "https://x.test/a.xml",
      text_url: "https://x.test/a.txt",
      source: source_ref()
    })

    assert [%BillVersion{plain_text: nil, text_source_id: nil}] = Repo.all(BillVersion)

    write!(%Records.BillVersionText{
      jurisdiction: @jur,
      bill_external_id: "119-hr-1",
      code: "ih",
      xml: "<bill/>",
      xml_schema: "uslm",
      plain_text: "text",
      source: source_ref()
    })

    [v] = Repo.all(BillVersion)
    assert v.text_source_id

    assert %{
             xml: "<bill/>",
             xml_schema: "uslm",
             plain_text: "text",
             date: ~D[2026-01-03],
             xml_url: "https://x.test/a.xml",
             text_url: "https://x.test/a.txt"
           } = v

    # Re-ingesting the version metadata keeps the stored text.
    write!(%Records.BillVersion{
      jurisdiction: @jur,
      bill_external_id: "119-hr-1",
      code: "ih",
      classification: "introduced",
      date: ~D[2026-01-03],
      xml_url: "https://x.test/a.xml",
      text_url: "https://x.test/a.txt",
      source: source_ref()
    })

    assert [%BillVersion{plain_text: "text"}] = Repo.all(BillVersion)
  end

  test "text for an unknown version returns an error" do
    write!(bill())

    assert {:error, {:unknown_bill_version, {"119-hr-1", "zz"}}} =
             Ingest.write(
               %Records.BillVersionText{
                 jurisdiction: @jur,
                 bill_external_id: "119-hr-1",
                 code: "zz",
                 xml: "<a/>",
                 xml_schema: "other",
                 plain_text: "t",
                 source: source_ref()
               },
               nil
             )
  end

  test "writing the same bill, actions and sponsorships twice leaves counts unchanged" do
    write_all = fn ->
      write!(bill())
      write!(actions([action(1), action(2)]))
      write!(sponsorships([%{person: {"id", "P1"}, classification: "primary"}]))
    end

    write_all.()
    before = {count(Bill), count(BillAction), count(Sponsorship)}
    write_all.()
    assert {count(Bill), count(BillAction), count(Sponsorship)} == before
    assert before == {1, 2, 1}
  end

  defp summaries(list) do
    %Records.BillSummaries{
      jurisdiction: @jur,
      bill_external_id: "119-hr-1",
      author: "Research office",
      summaries: list,
      source: source_ref()
    }
  end

  defp summary(code, date, html) do
    %{
      version_code: code,
      action_date: date,
      action_description: "Introduced",
      html: html,
      updated_at_source: nil
    }
  end

  test "summaries replace the bill's set; the latest is the newest action date" do
    write!(bill())

    write!(
      summaries([
        summary("00", ~D[2025-01-03], "<p>old</p>"),
        summary("36", ~D[2025-04-10], "<p>new</p>")
      ])
    )

    write!(summaries([summary("36", ~D[2025-04-10], "<p>newer</p>")]))

    bill = Legislation.get_bill(@jur, "119-hr-1")
    assert Repo.aggregate(EverydayCitizen.Legislation.BillSummary, :count) == 1
    assert %{html: "<p>newer</p>", author: "Research office"} = Legislation.latest_summary(bill)
  end

  test "a bill with no summaries has no latest summary" do
    write!(bill())
    assert Legislation.latest_summary(Legislation.get_bill(@jur, "119-hr-1")) == nil
  end
end
