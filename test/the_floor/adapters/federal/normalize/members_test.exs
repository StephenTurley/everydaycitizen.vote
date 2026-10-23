defmodule TheFloor.Adapters.Federal.Normalize.MembersTest do
  use ExUnit.Case, async: true

  alias TheFloor.Adapters.Federal.Normalize.Members
  alias TheFloor.Ingest.Records.{Membership, Person, SourceRef}

  @dir "test/support/fixtures/federal/legislators"
  @session_start ~D[2025-01-03]

  defp load(name), do: @dir |> Path.join(name) |> File.read!() |> JSON.decode!()
  defp source, do: SourceRef.new("https://example.test/x.json", "x")

  defp records do
    Members.records(
      load("legislators-current.json") ++ load("legislators-historical.json"),
      @session_start,
      source()
    )
  end

  defp memberships(records, bioguide) do
    for %Membership{person: {"bioguide", ^bioguide}} = m <- records, do: m
  end

  test "builds one person per legislator with the identifiers present" do
    people = for %Person{} = p <- records(), do: p
    assert length(people) == 4

    cantwell = Enum.find(people, &({"bioguide", "C000127"} in &1.identifiers))
    assert {"lis", "S275"} in cantwell.identifiers
    assert {"govtrack", "300018"} in cantwell.identifiers
    assert {"thomas", "00172"} in cantwell.identifiers
    assert cantwell.name == "Maria Cantwell"
    assert cantwell.family_name == "Cantwell"
    assert cantwell.given_name == "Maria"

    begich = Enum.find(people, &({"bioguide", "B001323"} in &1.identifiers))
    refute Enum.any?(begich.identifiers, fn {scheme, _} -> scheme == "lis" end)
  end

  test "at-large House district is STATE-AL" do
    assert [%Membership{} = m] =
             records() |> memberships("B001323") |> Enum.filter(&(&1.body_external_id == "house"))

    assert m.district == "AK-AL"
    assert m.role == "member"
    assert m.jurisdiction == "federal"
  end

  test "senator district is the state" do
    assert [m | _] = memberships(records(), "B001267")
    assert m.body_external_id == "senate"
    assert m.district == "CO"
    assert m.party == "Democrat"
  end

  test "member with two terms overlapping the session gets two memberships" do
    ms = memberships(records(), "C000127")
    assert length(ms) == 2
    assert Enum.map(ms, & &1.start_date) |> Enum.sort(Date) == [~D[2019-01-03], ~D[2025-01-03]]
  end

  test "historical member whose last term ended before the session is excluded" do
    all = records()
    assert memberships(all, "J000308") == []

    refute Enum.any?(all, fn
             %Person{identifiers: ids} -> {"bioguide", "J000308"} in ids
             _ -> false
           end)

    assert [_] = memberships(all, "B000944")
  end

  test "people come before memberships" do
    {people, rest} = records() |> Enum.split_while(&match?(%Person{}, &1))
    assert people != []
    assert Enum.all?(rest, &match?(%Membership{}, &1))
  end
end
