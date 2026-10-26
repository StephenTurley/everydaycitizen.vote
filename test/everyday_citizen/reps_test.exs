defmodule EverydayCitizen.RepsTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Reps

  @dir "test/support/fixtures/federal/census"

  setup do
    src = Records.SourceRef.new("https://x.test/a", "a")

    {:ok, _} =
      Ingest.write(
        %Records.Jurisdiction{
          key: "federal",
          name: "F",
          classification: "federal",
          time_zone: "America/New_York",
          source: src
        },
        nil
      )

    for id <- ~w(house senate) do
      {:ok, _} =
        Ingest.write(
          %Records.Body{
            jurisdiction: "federal",
            external_id: id,
            name: String.capitalize(id),
            classification: "chamber",
            source: src
          },
          nil
        )
    end

    for {id, name, body, district, end_date} <- [
          {"G1", "Chuck Grassley", "senate", "IA", ~D[2029-01-03]},
          {"E1", "Joni Ernst", "senate", "IA", ~D[2027-01-03]},
          {"M1", "Mariannette Miller-Meeks", "house", "IA-1", ~D[2027-01-03]},
          {"X1", "Gone Senator", "senate", "IA", ~D[2021-01-03]},
          {"N1", "Eleanor Holmes Norton", "house", "DC-AL", ~D[2027-01-03]}
        ] do
      {:ok, _} =
        Ingest.write(
          %Records.Person{identifiers: [{"bioguide", id}], name: name, source: src},
          nil
        )

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

    :ok
  end

  defp stub(file) do
    Req.Test.stub(EverydayCitizen.Federal, fn conn ->
      Plug.Conn.send_resp(conn, 200, File.read!("#{@dir}/#{file}"))
    end)
  end

  test "an address finds its current senators, then its representative" do
    stub("iowa_city.json")
    assert {:ok, "IA-1", reps} = Reps.find("400 S Clinton St, Iowa City, IA 52240")

    assert Enum.map(reps, & &1.person.name) == [
             "Chuck Grassley",
             "Joni Ernst",
             "Mariannette Miller-Meeks"
           ]

    assert Enum.all?(reps, &(&1.membership && &1.body))
  end

  test "a place with no senators gets only its delegate" do
    stub("dc.json")

    assert {:ok, "DC-AL", [%{person: %{name: "Eleanor Holmes Norton"}}]} =
             Reps.find("1600 Pennsylvania Ave NW")
  end

  test "a district key alone rebuilds the reps" do
    assert Enum.map(Reps.for_district("IA-1"), & &1.person.name) == [
             "Chuck Grassley",
             "Joni Ernst",
             "Mariannette Miller-Meeks"
           ]

    assert Reps.for_district("nonsense") == []
  end

  test "lookup failures pass through" do
    stub("no_match.json")
    assert {:error, :not_found} = Reps.find("nowhere")
  end

  test "place lists a state's senators then House members; nil for no place" do
    assert %{name: "Iowa", reps: reps} = Reps.place("Iowa")

    assert Enum.map(reps, & &1.person.name) == [
             "Chuck Grassley",
             "Joni Ernst",
             "Mariannette Miller-Meeks"
           ]

    assert Reps.place("nowhere") == nil
  end

  test "district_label" do
    assert Reps.district_label("IA-1") == "Iowa's 1st district"
    assert Reps.district_label(nil) == nil
  end
end
