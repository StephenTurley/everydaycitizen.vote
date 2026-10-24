defmodule TheFloor.BillPageTest do
  use TheFloor.DataCase, async: true

  alias TheFloor.{BillPage, Reps}
  alias TheFloor.Ingest
  alias TheFloor.Ingest.Records

  @src Records.SourceRef.new("https://www.congress.gov/x", "x")

  setup do
    people = TheFloor.FloorFixtures.iowa!()
    Map.put(people, :reps, Reps.for_district("IA-1"))
  end

  defp bill!(id, classification, actions) do
    {:ok, _} =
      Ingest.write(
        %Records.Bill{
          jurisdiction: "federal",
          session_identifier: "119",
          external_id: id,
          identifier: id,
          classification: classification,
          title: "T",
          from_body_external_id: "house",
          introduced_on: ~D[2026-02-01],
          source: @src
        },
        nil
      )

    {:ok, _} =
      Ingest.write(
        %Records.BillActions{
          jurisdiction: "federal",
          bill_external_id: id,
          actions:
            for {{date, c, actor}, i} <- Enum.with_index(actions) do
              %Records.BillAction{
                position: i,
                date: date,
                description: "a#{i}",
                classification: c,
                actor_body_external_id: actor
              }
            end,
          source: @src
        },
        nil
      )

    {:ok, page} = BillPage.load("federal", id, [])
    page
  end

  defp steps(page), do: Enum.map(page.steps, &{&1.label, &1.state})

  test "a bill passed by its first chamber is now in the second", %{reps: reps} do
    {:ok, page} = BillPage.load("federal", "119-s-5", reps)

    assert steps(page) == [
             {"Introduced", :done},
             {"Committee", :done},
             {"Senate", :done},
             {"House of Representatives", :current},
             {"Law", :todo}
           ]

    assert page.sponsor.name == "Joni Ernst"
    assert page.cosponsor_count == 1
    assert page.latest_action.position == 1
  end

  test "a law has every step done" do
    page =
      bill!("119-hr-9", "bill", [
        {~D[2026-02-01], "introduced", "house"},
        {~D[2026-03-01], "reported", "house"},
        {~D[2026-04-01], "passed_chamber", nil},
        {~D[2026-05-01], "passed_chamber", nil},
        {~D[2026-06-01], "became_law", nil}
      ])

    assert Enum.all?(page.steps, &(&1.state == :done))
    assert List.last(page.steps).date == ~D[2026-06-01]
  end

  test "a simple resolution ends at Agreed to, with no Law step" do
    page =
      bill!("119-hres-3", "resolution", [
        {~D[2026-02-01], "introduced", "house"},
        {~D[2026-02-03], "passed_chamber", "house"}
      ])

    assert steps(page) == [{"Introduced", :done}, {"Committee", :done}, {"Agreed to", :done}]
  end

  test "a bill only referred is in committee" do
    page =
      bill!("119-hr-10", "bill", [
        {~D[2026-02-01], "introduced", "house"},
        {~D[2026-02-01], "referred", "house"}
      ])

    assert [{"Introduced", :done}, {"Committee", :current} | rest] = steps(page)
    assert Enum.all?(rest, &(elem(&1, 1) == :todo))
  end

  test "your reps: a vote, a sponsor and a chamber that has not voted", %{reps: reps} do
    {:ok, page} = BillPage.load("federal", "119-s-5", reps)
    by_name = Map.new(page.reps, &{&1.person.name, &1.state})

    # Grassley cosponsored but his vote is what the bill page shows for a senator who voted
    assert by_name["Chuck Grassley"] == "yea"
    assert by_name["Joni Ernst"] == :sponsor
    assert by_name["Mariannette Miller-Meeks"] == :no_vote
  end

  test "versions, summary and votes", %{reps: reps} do
    {:ok, page} = BillPage.load("federal", "119-s-5", reps)
    assert page.versions == []
    assert page.summary == nil
    assert [%{external_id: "senate-119-2-7", body: %{name: "Senate"}}] = page.votes
  end

  test "an unknown bill is not found" do
    assert BillPage.load("federal", "119-hr-99999", []) == :not_found
  end

  test "votes on the same day are newest roll call first" do
    src = Records.SourceRef.new("https://x.test/v", "v")

    for {id, roll} <- [{"senate-119-2-8", "Roll Call 8"}, {"senate-119-2-9", "Roll Call 9"}] do
      {:ok, _} =
        Ingest.write(
          %Records.Vote{
            jurisdiction: "federal",
            body_external_id: "senate",
            session_identifier: "119-2",
            external_id: id,
            identifier: roll,
            question: "On the Amendment",
            voted_at: ~U[2026-01-21 05:00:00Z],
            bill_external_id: "119-s-5",
            counts: %{yea: 1, nay: 0, present: 0, absent: 0},
            positions: [],
            source: src
          },
          nil
        )
    end

    {:ok, page} = BillPage.load("federal", "119-s-5", [])
    assert Enum.map(page.votes, & &1.identifier) == ["Roll Call 9", "Roll Call 8", "Roll Call 7"]
  end

  test "versions are listed without their text; sections load for one version" do
    src = Records.SourceRef.new("https://x.test/t", "t")

    {:ok, _} =
      Ingest.write(
        %Records.BillVersion{
          jurisdiction: "federal",
          bill_external_id: "119-s-5",
          code: "is",
          source: src
        },
        nil
      )

    bill = TheFloor.Legislation.get_bill("federal", "119-s-5")
    v = TheFloor.Legislation.get_version(bill, "is")

    TheFloor.Repo.update_all(TheFloor.Legislation.BillVersion,
      set: [xml: "<bill/>", plain_text: "text"]
    )

    :ok = TheFloor.Legislation.put_sections(v.id, [%{"kind" => "section", "enum" => "1."}])

    {:ok, page} = BillPage.load("federal", "119-s-5", [])
    assert [%{code: "is", xml: nil, plain_text: nil, sections: nil}] = page.versions
    assert [%{"enum" => "1."}] = BillPage.sections(page.bill, "is")
  end
end
