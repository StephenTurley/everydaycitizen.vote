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
    member!("H2", "Zed Second", "house", "IA-2", ~D[2031-01-03])
    member!("H10", "Abe Tenth", "house", "IA-10", ~D[2031-01-03])
    member!("H3", "Iowa Ernst", "house", "IA-3", ~D[2031-01-03])
    member!("F1", "Aaron Joni", "senate", "IA", ~D[2023-01-03])
    member!("Z1", "Zora", nil, nil, nil)
    member!("Z2", "Aaron Zora", nil, nil, nil)
    member!("AK0", "Zack At-Large", "house", "AK-AL", ~D[2031-01-03])
    member!("AK1", "Amy One", "house", "AK-1", ~D[2031-01-03])
    member!("AK2", "Bob Two", "house", "AK-2", ~D[2031-01-03])
    member!("S1", "Iowa Smith", nil, nil, nil)
    :ok
  end

  test "a state lists its senators, then its House members in district order" do
    %{place: %{name: "Iowa", reps: reps}} = Search.people(search("iowa"), 20)

    assert Enum.map(reps, & &1.membership.district) == [
             "IA",
             "IA",
             "IA-1",
             "IA-2",
             "IA-3",
             "IA-10"
           ]
  end

  test "a name finds the person, tolerating a small typo" do
    assert %{people: [%{person: %{name: "Joni Ernst"}, body: %{external_id: "senate"}} | _]} =
             Search.people(search("Joni Ernst"), 10)

    assert %{people: [%{person: %{name: "Chuck Grassley"}} | _]} =
             Search.people(search("chuck grasley"), 10)
  end

  test "former members are found too, after those in office" do
    assert [%{person: %{name: "Joni Ernst"}}, %{person: %{name: "Aaron Joni"}}] =
             Search.people(search("joni"), 10).people
  end

  test "a query naming a place and a person shows both" do
    assert %{place: %{name: "Iowa"}, people: [%{person: %{name: "Iowa Smith"}, membership: nil}]} =
             Search.people(search("iowa"), 10)
  end

  test "a query with no words matches no one" do
    assert %{place: nil, people: []} = Search.people(search("!!!"), 10)
  end

  test "a place's members are listed under it, not again in people" do
    %{place: %{reps: reps}, people: people} = Search.people(search("iowa"), 10)

    assert "Iowa Ernst" in Enum.map(reps, & &1.person.name)
    refute "Iowa Ernst" in Enum.map(people, & &1.person.name)
  end

  test "a whole-name match comes before a longer name containing it, whatever the names' order" do
    assert [%{person: %{name: "Zora"}}, %{person: %{name: "Aaron Zora"}}] =
             Search.people(search("zora"), 10).people
  end

  test "only a chamber membership makes someone current" do
    src = source_ref()

    {:ok, _} =
      Ingest.write(
        %Records.Body{
          jurisdiction: "federal",
          external_id: "ways",
          name: "Ways",
          classification: "committee",
          source: src
        },
        nil
      )

    member!("C1", "Cora Former", "senate", "IA", ~D[2023-01-03])
    member!("C2", "Zed Cora", "senate", "IA", ~D[2031-01-03])

    {:ok, _} =
      Ingest.write(
        %Records.Membership{
          jurisdiction: "federal",
          person: {"bioguide", "C1"},
          body_external_id: "ways",
          role: "member",
          start_date: ~D[2019-01-03],
          source: src
        },
        nil
      )

    assert [%{person: %{name: "Zed Cora"}}, %{person: %{name: "Cora Former"}}] =
             Search.people(search("cora"), 10).people
  end

  test "at-large seats come before numbered ones under a prefix" do
    reps =
      EverydayCitizen.Legislature.current_members_matching(
        "federal",
        [{"house", {:prefix, "AK-"}}],
        ~D[2026-06-01]
      )

    assert Enum.map(reps, & &1.membership.district) == ["AK-AL", "AK-1", "AK-2"]
  end
end
