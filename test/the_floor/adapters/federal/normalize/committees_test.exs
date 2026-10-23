defmodule TheFloor.Adapters.Federal.Normalize.CommitteesTest do
  use ExUnit.Case, async: true

  alias TheFloor.Adapters.Federal.Normalize.Committees
  alias TheFloor.Ingest.Records.{Body, Membership, SourceRef}

  @dir "test/support/fixtures/federal/legislators"

  defp load(name), do: @dir |> Path.join(name) |> File.read!() |> JSON.decode!()

  defp records do
    Committees.records(
      load("committees-current.json"),
      load("committee-membership-current.json"),
      SourceRef.new("https://example.test/x.json", "x")
    )
  end

  defp bodies, do: for(%Body{} = b <- records(), do: b)
  defp memberships, do: for(%Membership{} = m <- records(), do: m)

  test "committee and subcommittee external ids match Congress.gov system codes" do
    by_id = Map.new(bodies(), &{&1.external_id, &1})

    assert %Body{classification: "committee", parent_external_id: "house"} = by_id["hsag00"]
    assert %Body{classification: "subcommittee", parent_external_id: "hsag00"} = by_id["hsag03"]
    assert by_id["hsag03"].name == "Nutrition and Foreign Agriculture"
  end

  test "joint committees hang off the legislature body" do
    assert %Body{parent_external_id: "congress"} =
             Enum.find(bodies(), &(&1.external_id == "jsec00"))
  end

  test "parent bodies precede their subcommittees" do
    ids = Enum.map(bodies(), & &1.external_id)
    assert Enum.find_index(ids, &(&1 == "hsag00")) < Enum.find_index(ids, &(&1 == "hsag03"))
  end

  test "titles map to roles" do
    roles = Map.new(memberships(), &{{&1.person, &1.body_external_id}, &1.role})

    assert roles[{{"bioguide", "B001323"}, "hsag00"}] == "chair"
    assert roles[{{"bioguide", "C000127"}, "hsag00"}] == "ranking_member"
    assert roles[{{"bioguide", "B001323"}, "hsag03"}] == "member"
    assert roles[{{"bioguide", "B001267"}, "jsec00"}] == "vice_chair"
    assert roles[{{"bioguide", "Z999999"}, "jsec00"}] == "chair"
  end

  test "committee memberships carry no dates" do
    assert Enum.all?(memberships(), &(is_nil(&1.start_date) and is_nil(&1.end_date)))
  end
end
