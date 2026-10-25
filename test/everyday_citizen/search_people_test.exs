defmodule EverydayCitizen.SearchPeopleTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.FloorFixtures
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Search
  alias EverydayCitizen.Search.Query

  defp search(q) do
    {:search, query} = Query.classify(q)
    query
  end

  defp member!(id, name, body, district, end_date) do
    src = source_ref()

    {:ok, _} =
      Ingest.write(%Records.Person{identifiers: [{"bioguide", id}], name: name, source: src}, nil)

    if body do
      {:ok, _} =
        Ingest.write(
          %Records.Membership{
            jurisdiction: "federal",
            person: {"bioguide", id},
            body_external_id: body,
            role: "member",
            district: district,
            start_date: ~D[2019-01-03],
            end_date: end_date,
            source: src
          },
          nil
        )
    end
  end

  setup do
    FloorFixtures.iowa!()
    member!("H2", "Second District", "house", "IA-2", ~D[2031-01-03])
    member!("H10", "Tenth District", "house", "IA-10", ~D[2031-01-03])
    member!("F1", "Joni Ernstly", "senate", "IA", ~D[2023-01-03])
    member!("S1", "Iowa Smith", nil, nil, nil)
    :ok
  end

  test "a state lists its senators, then its House members in district order" do
    %{place: %{name: "Iowa", reps: reps}} = Search.people(search("iowa"), 20)

    assert Enum.map(reps, & &1.membership.district) == ["IA", "IA", "IA-1", "IA-2", "IA-10"]
  end

  test "a name finds the person, tolerating a small typo" do
    assert %{people: [%{person: %{name: "Joni Ernst"}, body: %{external_id: "senate"}} | _]} =
             Search.people(search("Joni Ernst"), 10)

    assert %{people: [%{person: %{name: "Chuck Grassley"}} | _]} =
             Search.people(search("chuck grasley"), 10)
  end

  test "former members are found too, after those in office" do
    assert [%{person: %{name: "Joni Ernst"}}, %{person: %{name: "Joni Ernstly"}}] =
             Search.people(search("joni"), 10).people
  end

  test "a query naming a place and a person shows both" do
    assert %{place: %{name: "Iowa"}, people: [%{person: %{name: "Iowa Smith"}, membership: nil}]} =
             Search.people(search("iowa"), 10)
  end

  test "a query with no words matches no one" do
    assert %{place: nil, people: []} = Search.people(search("!!!"), 10)
  end
end
