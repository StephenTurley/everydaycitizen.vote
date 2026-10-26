defmodule EverydayCitizen.Adapters.Federal.Normalize.HouseVoteTest do
  use ExUnit.Case, async: true

  alias EverydayCitizen.Adapters.Federal.Normalize.HouseVote
  alias EverydayCitizen.Ingest.Records.{SourceRef, Vote}

  @dir "test/support/fixtures/federal/congress_gov"

  defp json(name), do: @dir |> Path.join(name) |> File.read!() |> Jason.decode!()
  defp source, do: SourceRef.new("https://example.test/members.json", "x")

  defp vote(name),
    do: HouseVote.vote(json("#{name}.json"), json("#{name}_members.json"), source())

  test "list/1 returns roll, update date and legislation per item" do
    items = HouseVote.list(json("house_vote_list.json"))
    assert items |> Enum.map(& &1.roll) |> Enum.sort() == [2, 17, 240, 259, 306]
    assert Enum.find(items, &(&1.roll == 240)).updated_at == ~U[2025-09-09 22:53:19Z]
  end

  describe "vote on a bill (January, -05:00)" do
    setup do: %{vote: vote("house_vote_119_1_17")}

    test "identity and bill", %{vote: vote} do
      assert %Vote{} = vote
      assert vote.jurisdiction == "federal"
      assert vote.body_external_id == "house"
      assert vote.session_identifier == "119-1"
      assert vote.external_id == "house-119-1-17"
      assert vote.identifier == "Roll Call 17"
      assert vote.bill_external_id == "119-hr-30"
      assert vote.question == "On Passage"
      assert vote.classification == "passage"
      assert vote.result == "Passed"
      assert vote.passed == true
    end

    test "Eastern time to UTC", %{vote: vote} do
      assert vote.voted_at == ~U[2025-01-16 16:00:00Z]
    end

    test "counts are the party totals summed", %{vote: vote} do
      assert vote.counts == %{yea: 274, nay: 145, present: 0, absent: 15}
    end

    test "positions keyed by bioguide", %{vote: vote} do
      assert Enum.all?(vote.positions, &match?({"bioguide", _}, &1.person))
      by_id = Map.new(vote.positions, &{elem(&1.person, 1), &1})
      assert %{option: "yea", raw_option: "Yea", raw_label: "Aderholt (R-AL)"} = by_id["A000055"]
      assert by_id["A000148"].option == "nay"
      assert Enum.any?(vote.positions, &(&1.option == "absent" and &1.raw_option == "Not Voting"))
    end
  end

  test "Aye and No map to yea and nay; July timestamp uses -04:00" do
    vote = vote("house_vote_119_1_259")
    assert vote.voted_at == ~U[2025-09-10 21:36:00Z]
    assert vote.voted_on == ~D[2025-09-10]
    assert vote.passed == false
    assert vote.bill_external_id == "119-hr-3838"
    # an amendment vote names the amendment and links its official page
    assert vote.description == "Biggs of Arizona Part A Amendment No. 29"
    assert vote.subject_ref == "HAMDT97"
    assert vote.subject_url == "https://www.congress.gov/amendment/119/house-amendment/97"
    assert vote.counts.yea == 200
    options = Map.new(vote.positions, &{&1.raw_option, &1.option})
    assert %{"Aye" => "yea", "No" => "nay", "Not Voting" => "absent"} = options
  end

  test "a vote on a bill itself has no separate subject" do
    vote = vote("house_vote_119_1_17")
    assert vote.description == nil
    assert vote.subject_url == nil
  end

  test "a July timestamp converts with the summer offset" do
    detail =
      json("house_vote_119_1_17.json")
      |> Map.update!("houseRollCallVote", &Map.put(&1, "startDate", "2025-07-02T14:31:00-04:00"))

    vote = HouseVote.vote(detail, json("house_vote_119_1_17_members.json"), source())
    assert vote.voted_at == ~U[2025-07-02 18:31:00Z]
  end

  test "vote without legislation (Speaker election) has no bill; candidates are present" do
    vote = vote("house_vote_119_1_2")
    assert vote.bill_external_id == nil
    assert vote.external_id == "house-119-1-2"
    assert vote.passed == nil
    assert vote.counts == %{yea: 0, nay: 0, present: 434, absent: 0}
    assert Enum.all?(vote.positions, &(&1.option == "present"))
    assert "Jeffries" in Enum.map(vote.positions, & &1.raw_option)
  end
end
