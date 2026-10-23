defmodule TheFloor.Ingest.Writer.LegislatureTest do
  use TheFloor.DataCase, async: true

  alias TheFloor.Ingest
  alias TheFloor.Ingest.Records
  alias TheFloor.Legislature
  alias TheFloor.Legislature.{Body, Membership, Person, PersonIdentifier}

  @jur "fed"

  defp jurisdiction do
    {:ok, j} =
      Ingest.write(
        %Records.Jurisdiction{
          key: @jur,
          name: "Fed",
          classification: "federal",
          source: source_ref()
        },
        nil
      )

    j
  end

  defp body(external_id, classification, parent \\ nil) do
    %Records.Body{
      jurisdiction: @jur,
      external_id: external_id,
      name: external_id,
      classification: classification,
      parent_external_id: parent,
      source: source_ref()
    }
  end

  defp person(identifiers) do
    %Records.Person{identifiers: identifiers, name: "P", source: source_ref()}
  end

  defp membership(attrs) do
    struct!(
      %Records.Membership{
        jurisdiction: @jur,
        person: {"a", "1"},
        body_external_id: "lower",
        role: "member",
        source: source_ref()
      },
      attrs
    )
  end

  defp seed do
    jurisdiction()
    {:ok, _} = Ingest.write(body("lower", "chamber"), nil)
    {:ok, _} = Ingest.write(person([{"a", "1"}]), nil)
  end

  test "writes a body tree" do
    jurisdiction()
    {:ok, _} = Ingest.write(body("lower", "chamber"), nil)
    {:ok, _} = Ingest.write(body("cmte-1", "committee", "lower"), nil)
    {:ok, sub} = Ingest.write(body("sub-1", "subcommittee", "cmte-1"), nil)

    assert Repo.preload(sub, :parent).parent.external_id == "cmte-1"
    assert Legislature.get_body(@jur, "lower").classification == "chamber"
  end

  test "unknown parent body returns an error" do
    jurisdiction()
    assert {:error, {:unknown_parent, "nope"}} = Ingest.write(body("x", "committee", "nope"), nil)
  end

  test "writes sessions with a parent" do
    jurisdiction()
    base = %Records.LegislativeSession{jurisdiction: @jur, identifier: "s1", source: source_ref()}
    {:ok, _} = Ingest.write(base, nil)

    {:ok, child} =
      Ingest.write(
        %{base | identifier: "s1-1", parent_identifier: "s1", source: source_ref()},
        nil
      )

    assert Repo.preload(child, :parent).parent.identifier == "s1"
    assert Legislature.get_session(@jur, "s1-1").id == child.id
  end

  test "person matched by any identifier" do
    {:ok, first} = Ingest.write(person([{"a", "1"}]), nil)
    {:ok, second} = Ingest.write(person([{"a", "1"}, {"b", "9"}]), nil)

    assert first.id == second.id
    assert Repo.aggregate(Person, :count) == 1
    assert Repo.aggregate(PersonIdentifier, :count) == 2
    assert Legislature.get_person_by_identifier("b", "9").id == first.id
  end

  test "membership upsert is idempotent" do
    seed()
    rec = membership(start_date: ~D[2025-01-03])
    {:ok, a} = Ingest.write(rec, nil)
    {:ok, b} = Ingest.write(%{rec | party: "x", source: source_ref()}, nil)

    assert a.id == b.id
    assert Repo.aggregate(Membership, :count) == 1
    assert Repo.get!(Membership, a.id).party == "x"
  end

  test "membership with nil start_date written twice yields one row" do
    seed()
    {:ok, _} = Ingest.write(body("cmte-1", "committee"), nil)
    rec = membership(body_external_id: "cmte-1", role: "chair", start_date: nil)
    {:ok, a} = Ingest.write(rec, nil)
    {:ok, b} = Ingest.write(%{rec | source: source_ref()}, nil)

    assert a.id == b.id
    assert Repo.aggregate(Membership, :count) == 1
  end

  test "writing the same records twice leaves counts unchanged" do
    records = fn ->
      [
        %Records.Jurisdiction{
          key: @jur,
          name: "Fed",
          classification: "federal",
          source: source_ref()
        },
        body("lower", "chamber"),
        body("cmte-1", "committee", "lower"),
        person([{"a", "1"}, {"b", "2"}]),
        membership(start_date: ~D[2025-01-03]),
        membership(body_external_id: "cmte-1", start_date: nil)
      ]
    end

    counts = fn ->
      Enum.map([Body, Person, PersonIdentifier, Membership], &Repo.aggregate(&1, :count))
    end

    Enum.each(records.(), &({:ok, _} = Ingest.write(&1, nil)))
    first = counts.()
    Enum.each(records.(), &({:ok, _} = Ingest.write(&1, nil)))

    assert counts.() == first
  end

  test "membership referencing unknown person returns an error" do
    seed()

    assert {:error, {:unknown_person, {"a", "x"}}} =
             Ingest.write(membership(person: {"a", "x"}), nil)
  end

  test "failed write does not leave a source row behind" do
    seed()
    before = Repo.aggregate(TheFloor.Provenance.Source, :count)
    {:error, _} = Ingest.write(membership(person: {"a", "x"}), nil)
    assert Repo.aggregate(TheFloor.Provenance.Source, :count) == before
  end

  test "current_memberships/2 excludes ended memberships and counts a mid-term replacement once" do
    seed()
    {:ok, _} = Ingest.write(person([{"a", "2"}]), nil)

    {:ok, _} =
      Ingest.write(
        membership(district: "7", start_date: ~D[2025-01-03], end_date: ~D[2026-03-01]),
        nil
      )

    {:ok, b} =
      Ingest.write(membership(person: {"a", "2"}, district: "7", start_date: ~D[2026-03-05]), nil)

    body = Legislature.get_body(@jur, "lower")
    assert [current] = Legislature.current_memberships(body.id, ~D[2026-06-01])
    assert current.id == b.id
  end
end
