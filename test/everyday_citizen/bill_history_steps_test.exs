defmodule EverydayCitizen.BillHistoryStepsTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.BillHistory
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Legislation

  @src Records.SourceRef.new("https://x.test/v", "v")

  defp w(record) do
    {:ok, row} = Ingest.write(record, nil)
    row
  end

  setup do
    people = EverydayCitizen.FloorFixtures.iowa!()

    w(%Records.Body{
      jurisdiction: "federal",
      external_id: "ssju00",
      name: "Senate Committee on the Judiciary",
      classification: "committee",
      source: @src
    })

    w(%Records.Membership{
      jurisdiction: "federal",
      person: {"bioguide", "G000386"},
      body_external_id: "ssju00",
      role: "member",
      source: @src
    })

    for {code, date} <- [{"is", ~D[2026-01-06]}, {"es", ~D[2026-01-25]}],
        do:
          w(%Records.BillVersion{
            jurisdiction: "federal",
            bill_external_id: "119-s-5",
            code: code,
            classification: code,
            date: date,
            source: @src
          })

    w(%Records.BillCommittees{
      jurisdiction: "federal",
      bill_external_id: "119-s-5",
      activities: [
        %{body_external_id: "ssju00", kind: "referred", date: ~D[2026-01-06]},
        %{body_external_id: "ssju00", kind: "markup", date: ~D[2026-01-15]}
      ],
      source: @src
    })

    w(%Records.BillRelations{
      jurisdiction: "federal",
      bill_external_id: "119-s-5",
      relations: [%{bill_external_id: "119-sres-10", kind: "procedural"}],
      source: @src
    })

    w(%Records.BillAmendments{
      jurisdiction: "federal",
      bill_external_id: "119-s-5",
      amendments: [
        %{
          external_id: "119-samdt-1",
          identifier: "S.Amdt. 1",
          description: "In the nature of a substitute.",
          latest_action: "Agreed to by voice vote.",
          latest_action_date: ~D[2026-01-19],
          url: "https://example.test/samdt/1",
          agreed: true
        },
        %{
          external_id: "119-samdt-2",
          identifier: "S.Amdt. 2",
          description: "To strike everything.",
          latest_action: "Not agreed to.",
          latest_action_date: ~D[2026-01-19],
          url: "https://example.test/samdt/2",
          agreed: false
        }
      ],
      source: @src
    })

    # a vote on the rule (not stored as a bill), the day before passage
    w(%Records.Vote{
      jurisdiction: "federal",
      body_external_id: "senate",
      session_identifier: "119-2",
      external_id: "senate-119-2-6",
      identifier: "Roll Call 6",
      question: "On the Resolution",
      voted_at: ~U[2026-01-19 17:00:00Z],
      bill_external_id: "119-sres-10",
      positions: [
        %{person: {"bioguide", "E000295"}, raw_label: "Ernst", option: "yea", raw_option: "Yea"}
      ],
      source: @src
    })

    Map.put(people, :bill, Legislation.get_bill("federal", "119-s-5"))
  end

  test "each version's step gathers what happened since the version before", %{bill: bill} do
    assert [first, second] = BillHistory.steps(bill)

    assert %{code: "is", from_date: nil, date: ~D[2026-01-06]} = first
    assert [%{kind: "referred"}] = first.committees

    assert %{code: "es", from_date: ~D[2026-01-06], date: ~D[2026-01-25]} = second

    assert [%{kind: "markup", body: %{name: "Senate Committee on the Judiciary"}}] =
             second.committees

    # only amendments that were agreed to produced the text
    assert [%{identifier: "S.Amdt. 1"}] = second.amendments
    assert [%{identifier: "Roll Call 7"}] = second.votes
    assert [%{ref: "119-sres-10", vote: %{identifier: "Roll Call 6"}}] = second.related_votes
  end

  test "a rep's part in a step: their votes and a committee they sit on", %{
    bill: bill,
    grassley: g,
    ernst: e
  } do
    step = List.last(BillHistory.steps(bill))

    assert [grassley, ernst] = BillHistory.involvement(step, [g, e])

    assert grassley.person.id == g.id
    assert [{%{identifier: "Roll Call 7"}, "yea"}] = grassley.votes
    assert [%{name: "Senate Committee on the Judiciary"}] = grassley.committees

    # a referral is not the committee acting on the text
    first = List.first(BillHistory.steps(bill))
    assert [%{committees: []}] = BillHistory.involvement(first, [g])

    assert [{%{identifier: "Roll Call 6"}, "yea"}, {%{identifier: "Roll Call 7"}, "nay"}] =
             ernst.votes

    assert ernst.committees == []
  end

  test "a rep with nothing in a step has no votes and no committees", %{
    bill: bill,
    miller_meeks: m
  } do
    step = List.last(BillHistory.steps(bill))
    assert [%{votes: [], committees: []}] = BillHistory.involvement(step, [m])
  end
end
