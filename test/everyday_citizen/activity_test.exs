defmodule EverydayCitizen.ActivityTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.Activity
  alias EverydayCitizen.Activity.Item
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Legislature

  @src Records.SourceRef.new("https://x.test/a", "a")

  defp write!(r) do
    {:ok, row} = Ingest.write(r, nil)
    row
  end

  defp bill!(id, title) do
    write!(%Records.Bill{
      jurisdiction: "j",
      session_identifier: "1",
      external_id: id,
      identifier: id,
      classification: "bill",
      title: title,
      source: @src
    })
  end

  defp action(pos, date, classification),
    do: %Records.BillAction{
      position: pos,
      date: date,
      description: "a#{pos}",
      classification: classification
    }

  setup do
    write!(%Records.Jurisdiction{key: "j", name: "J", classification: "state", source: @src})
    write!(%Records.LegislativeSession{jurisdiction: "j", identifier: "1", source: @src})

    write!(%Records.Body{
      jurisdiction: "j",
      external_id: "upper",
      name: "Upper",
      classification: "chamber",
      source: @src
    })

    for id <- ~w(P1 P2),
        do: write!(%Records.Person{identifiers: [{"id", id}], name: id, source: @src})

    bill!("b-own", "Own bill")
    bill!("b-co", "Cosponsored bill")
    bill!("b-law", "Law bill")

    write!(%Records.Sponsorships{
      jurisdiction: "j",
      bill_external_id: "b-own",
      sponsorships: [
        %{
          person: {"id", "P1"},
          classification: "primary",
          date: ~D[2025-02-01],
          withdrawn_on: nil
        }
      ],
      source: @src
    })

    write!(%Records.Sponsorships{
      jurisdiction: "j",
      bill_external_id: "b-law",
      sponsorships: [
        %{
          person: {"id", "P1"},
          classification: "primary",
          date: ~D[2025-01-10],
          withdrawn_on: nil
        }
      ],
      source: @src
    })

    write!(%Records.Sponsorships{
      jurisdiction: "j",
      bill_external_id: "b-co",
      sponsorships: [
        %{
          person: {"id", "P2"},
          classification: "primary",
          date: ~D[2025-03-01],
          withdrawn_on: nil
        },
        %{
          person: {"id", "P1"},
          classification: "cosponsor",
          date: ~D[2025-03-02],
          withdrawn_on: nil
        }
      ],
      source: @src
    })

    write!(%Records.BillActions{
      jurisdiction: "j",
      bill_external_id: "b-own",
      actions: [
        action(0, ~D[2025-02-01], "introduced"),
        action(1, ~D[2025-02-02], "referred"),
        action(2, ~D[2025-04-01], "passed_chamber")
      ],
      source: @src
    })

    write!(%Records.BillActions{
      jurisdiction: "j",
      bill_external_id: "b-law",
      actions: [
        action(0, ~D[2025-05-01], "passed_chamber"),
        action(1, ~D[2025-06-01], "became_law")
      ],
      source: @src
    })

    write!(%Records.Vote{
      jurisdiction: "j",
      body_external_id: "upper",
      session_identifier: "1",
      external_id: "v1",
      question: "On Passage",
      voted_at: ~U[2025-04-01 16:00:00Z],
      bill_external_id: "b-co",
      counts: %{yea: 1, nay: 0, present: 0, absent: 0},
      positions: [%{person: {"id", "P1"}, raw_label: "P1", option: "yea", raw_option: "Yea"}],
      source: @src
    })

    %{
      p1: Legislature.get_person_by_identifier("id", "P1").id,
      p2: Legislature.get_person_by_identifier("id", "P2").id
    }
  end

  defp kinds(items), do: Enum.map(items, &{&1.kind, &1.date})

  test "everything they did, newest first; same-day progress before votes", %{p1: p1} do
    assert %{items: items, next: nil} = Activity.feed(p1, [])

    assert kinds(items) == [
             {:became_law, ~D[2025-06-01]},
             {:moved, ~D[2025-05-01]},
             {:moved, ~D[2025-04-01]},
             {:vote, ~D[2025-04-01]},
             {:introduced, ~D[2025-02-01]},
             {:introduced, ~D[2025-01-10]}
           ]

    assert %Item{
             kind: :vote,
             option: "yea",
             vote: %{external_id: "v1"},
             bill: %{external_id: "b-co"}
           } =
             Enum.find(items, &(&1.kind == :vote))
  end

  test "filters narrow to votes, their bills, or laws", %{p1: p1} do
    assert [:vote] = Activity.feed(p1, filter: :votes).items |> Enum.map(& &1.kind)

    assert Activity.feed(p1, filter: :bills).items
           |> Enum.map(& &1.kind)
           |> Enum.uniq()
           |> Enum.sort() == [:introduced, :moved]

    assert [:became_law] = Activity.feed(p1, filter: :law).items |> Enum.map(& &1.kind)
  end

  test "a cosponsored bill and referrals are not in the feed", %{p1: p1} do
    items = Activity.feed(p1, filter: :bills).items
    refute Enum.any?(items, &(&1.bill.external_id == "b-co"))
    refute Enum.any?(items, &(&1.action && &1.action.classification == "referred"))
  end

  test "pages walk every item exactly once", %{p1: p1} do
    all = Activity.feed(p1, []).items

    walk = fn walk, cursor, acc ->
      %{items: items, next: next} = Activity.feed(p1, limit: 2, before: cursor)
      if next, do: walk.(walk, next, acc ++ items), else: acc ++ items
    end

    assert kinds(walk.(walk, nil, [])) == kinds(all)
  end

  test "counts of bills sponsored and cosponsored", %{p1: p1} do
    assert Activity.counts(p1) == %{sponsored: 2, cosponsored: 1}
  end

  test "someone with no activity has an empty feed", %{p2: p2} do
    assert %{items: [_], next: nil} = Activity.feed(p2, [])
    assert %{items: [], next: nil} = Activity.feed(p2, filter: :votes)
  end

  test "a late-evening vote is on its Eastern date", %{p1: p1} do
    EverydayCitizen.Repo.update_all(EverydayCitizen.Votes.Vote,
      set: [voted_at: ~U[2025-04-02 00:30:00Z]]
    )

    assert [%{date: ~D[2025-04-01]}] = Activity.feed(p1, filter: :votes).items
  end
end
