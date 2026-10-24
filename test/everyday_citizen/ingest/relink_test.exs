defmodule EverydayCitizen.Ingest.RelinkTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.{Records, Relink}
  alias EverydayCitizen.Repo
  alias EverydayCitizen.Votes.{Vote, VotePosition}

  setup do
    for key <- ["a", "b"] do
      write!(%Records.Jurisdiction{key: key, name: key, classification: "state", source: src()})
      write!(%Records.LegislativeSession{jurisdiction: key, identifier: "1", source: src()})

      write!(%Records.Body{
        jurisdiction: key,
        external_id: "lower",
        name: "Lower",
        classification: "chamber",
        source: src()
      })
    end

    :ok
  end

  test "links votes and positions written before their bill and people; idempotent" do
    write!(vote("a", [{"id", "P1"}, {"id", "P2"}, nil]))
    assert {:ok, %{votes: 0, positions: 0}} = Relink.run()

    write!(bill("a", "hb-1"))
    write!(%Records.Person{identifiers: [{"id", "P1"}], name: "Pat", source: src()})

    assert {:ok, %{votes: 1, positions: 1}} = Relink.run()

    vote = Repo.one!(Vote) |> Repo.preload([:bill, :positions])
    assert vote.bill.external_id == "hb-1"
    assert Enum.count(vote.positions, & &1.person_id) == 1

    assert {:ok, %{votes: 0, positions: 0}} = Relink.run()
  end

  test "a vote links only to a bill of its own jurisdiction" do
    write!(vote("a", []))
    write!(bill("b", "hb-1"))

    assert {:ok, %{votes: 0}} = Relink.run()
    assert Repo.one!(Vote).bill_id == nil
  end

  test "positions already linked are left alone" do
    write!(%Records.Person{identifiers: [{"id", "P1"}], name: "Pat", source: src()})
    write!(vote("a", [{"id", "P1"}]))

    assert {:ok, %{positions: 0}} = Relink.run()
    assert Repo.one!(VotePosition).person_id
  end

  defp vote(jurisdiction, people) do
    %Records.Vote{
      jurisdiction: jurisdiction,
      body_external_id: "lower",
      session_identifier: "1",
      external_id: "v1",
      voted_at: ~U[2026-02-01 15:00:00Z],
      bill_external_id: "hb-1",
      counts: %{yea: length(people), nay: 0, present: 0, absent: 0},
      positions:
        for(
          person <- people,
          do: %{person: person, raw_label: "x", option: "yea", raw_option: "Y"}
        ),
      source: src()
    }
  end

  defp bill(jurisdiction, external_id) do
    %Records.Bill{
      jurisdiction: jurisdiction,
      session_identifier: "1",
      external_id: external_id,
      identifier: "HB 1",
      classification: "bill",
      title: "A bill",
      source: src()
    }
  end

  defp src, do: Records.SourceRef.new("https://example.test/#{System.unique_integer()}", "x")

  defp write!(record) do
    {:ok, row} = Ingest.write(record, nil)
    row
  end
end
