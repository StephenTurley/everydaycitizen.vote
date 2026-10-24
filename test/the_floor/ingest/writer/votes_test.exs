defmodule TheFloor.Ingest.Writer.VotesTest do
  use TheFloor.DataCase, async: true

  alias TheFloor.Ingest
  alias TheFloor.Ingest.Records
  alias TheFloor.Repo
  alias TheFloor.Votes
  alias TheFloor.Votes.{Vote, VotePosition}

  @jur "fed"

  setup do
    write!(%Records.Jurisdiction{
      key: @jur,
      name: "Fed",
      classification: "federal",
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

    write!(%Records.Bill{
      jurisdiction: @jur,
      session_identifier: "119",
      external_id: "119-hr-1",
      identifier: "HR 1",
      classification: "bill",
      title: "A bill",
      source: source_ref()
    })

    :ok
  end

  defp write!(record) do
    {:ok, row} = Ingest.write(record, nil)
    row
  end

  defp pos(person, option, label) do
    %{person: person, raw_label: label, option: option, raw_option: String.capitalize(option)}
  end

  defp vote(attrs \\ []) do
    struct!(
      %Records.Vote{
        jurisdiction: @jur,
        body_external_id: "lower",
        session_identifier: "119",
        external_id: "lower-119-1-5",
        identifier: "Roll 5",
        question: "On Passage",
        result: "Passed",
        passed: true,
        voted_at: ~U[2026-02-01 15:00:00Z],
        bill_external_id: "119-hr-1",
        counts: %{yea: 2, nay: 0, present: 0, absent: 0},
        positions: [pos({"id", "P1"}, "yea", "Pat"), pos({"id", "P2"}, "yea", "Sam")],
        source: source_ref()
      },
      attrs
    )
  end

  test "writes a vote with positions and links the bill" do
    v = write!(vote())
    assert v.bill_id
    assert v.yea_count == 2
    assert Repo.aggregate(VotePosition, :count) == 2
  end

  test "keeps positions for unknown people" do
    positions = [
      pos({"id", "P1"}, "yea", "Pat"),
      pos({"x", "nope"}, "nay", "Nobody"),
      pos(nil, "absent", "Ghost")
    ]

    v = write!(vote(positions: positions))
    rows = Repo.all(from p in VotePosition, where: p.vote_id == ^v.id, order_by: p.id)

    assert [
             %{person_id: pid},
             %{person_id: nil, raw_label: "Nobody"},
             %{person_id: nil, raw_label: "Ghost"}
           ] = rows

    assert pid
  end

  test "vote without legislation has nil bill_id" do
    assert write!(vote(bill_external_id: nil)).bill_id == nil
    v = write!(vote(external_id: "other", bill_external_id: "missing"))
    assert v.bill_id == nil
  end

  test "re-ingesting a vote replaces positions and is idempotent" do
    v = write!(vote())
    write!(vote())
    assert Repo.aggregate(Vote, :count) == 1
    assert Repo.aggregate(VotePosition, :count) == 2

    write!(
      vote(
        positions: [pos({"id", "P1"}, "nay", "Pat")],
        counts: %{yea: 0, nay: 1, present: 0, absent: 0}
      )
    )

    assert [%{option: "nay"}] = Repo.all(VotePosition)
    {:ok, body} = {:ok, Repo.get!(Vote, v.id)}
    assert Votes.count_votes(body.body_id, body.session_id) == 1
  end

  test "stores the source's bill and person references, linked or not" do
    v = write!(vote(bill_external_id: "119-hr-9", positions: [pos({"x", "nope"}, "nay", "N")]))
    assert %{bill_id: nil, bill_ref: "119-hr-9"} = v

    assert [%{person_id: nil, person_scheme: "x", person_value: "nope"}] =
             Repo.all(VotePosition)

    write!(vote(external_id: "linked"))
    linked = Repo.get_by!(Vote, external_id: "linked")
    assert linked.bill_id && linked.bill_ref == "119-hr-1"
  end

  test "a vote without a body is an error" do
    assert {:error, {:unknown_body, nil}} = Ingest.write(vote(body_external_id: nil), nil)
  end

  test "unknown body or session is an error" do
    assert {:error, {:unknown_body, "nope"}} = Ingest.write(vote(body_external_id: "nope"), nil)
    assert {:error, {:unknown_session, "1"}} = Ingest.write(vote(session_identifier: "1"), nil)
  end

  # A large chamber's vote has ~430 positions; one query per position (plus a lookup
  # each) ran past the 15 s transaction timeout on a loaded database.
  test "positions are written in a fixed number of queries, however many there are" do
    positions =
      for i <- 1..60 do
        person = Enum.at([{"id", "P1"}, {"id", "P2"}, {"id", "NOBODY#{i}"}], rem(i, 3))
        pos(person, "yea", "Member #{i}")
      end

    test_pid = self()
    handler = "count-queries-#{inspect(test_pid)}"

    :telemetry.attach(
      handler,
      [:the_floor, :repo, :query],
      fn _, _, _, _ ->
        if self() == test_pid, do: send(test_pid, :query)
      end,
      nil
    )

    write!(vote(positions: positions, counts: %{yea: 60, nay: 0, present: 0, absent: 0}))
    :telemetry.detach(handler)

    queries =
      Stream.repeatedly(fn ->
        receive do
          :query -> 1
        after
          0 -> nil
        end
      end)
      |> Enum.take_while(& &1)
      |> length()

    assert queries <= 15, "wrote 60 positions in #{queries} queries"
    assert Repo.aggregate(VotePosition, :count) == 60
    assert Repo.aggregate(from(p in VotePosition, where: not is_nil(p.person_id)), :count) == 40
  end

  test "a position with an invalid option fails the write and stores none of its positions" do
    bad = vote(positions: [pos({"id", "P1"}, "yea", "Pat"), pos({"id", "P2"}, "maybe", "Sam")])
    assert {:error, _} = Ingest.write(bad, nil)
    assert Repo.aggregate(VotePosition, :count) == 0
  end

  test "option outside yea/nay/present/absent is rejected by changeset" do
    cs =
      VotePosition.changeset(%VotePosition{}, %{
        vote_id: 1,
        option: "maybe",
        raw_label: "x",
        source_id: 1
      })

    assert %{option: [_]} = errors_on(cs)
  end
end
