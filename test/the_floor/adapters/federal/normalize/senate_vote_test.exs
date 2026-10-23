defmodule TheFloor.Adapters.Federal.Normalize.SenateVoteTest do
  use ExUnit.Case, async: true

  alias TheFloor.Adapters.Federal.Normalize.SenateVote
  alias TheFloor.Ingest.Records.{SourceRef, Vote}

  @dir "test/support/fixtures/federal/senate"

  defp read(name), do: File.read!(Path.join(@dir, name))
  defp source, do: SourceRef.new("https://example.test/vote.xml", "x")

  test "menu/1 returns the roll numbers" do
    assert SenateVote.menu(read("vote_menu_119_1.xml")) == [5, 4, 3, 2, 1]
  end

  describe "vote/2 on a bill" do
    setup do
      %{vote: SenateVote.vote(read("vote_119_1_00001.xml"), source())}
    end

    test "identity, bill and question", %{vote: vote} do
      assert %Vote{} = vote
      assert vote.jurisdiction == "federal"
      assert vote.body_external_id == "senate"
      assert vote.session_identifier == "119-1"
      assert vote.external_id == "senate-119-1-1"
      assert vote.bill_external_id == "119-s-5"
      assert vote.question == "On the Motion to Proceed"
      assert vote.result == "Motion Agreed to"
      assert vote.passed == true
    end

    test "parses the Eastern time vote date into UTC", %{vote: vote} do
      assert vote.voted_at == ~U[2025-01-09 17:04:00Z]
    end

    test "count totals", %{vote: vote} do
      assert vote.counts == %{yea: 84, nay: 9, present: 0, absent: 7}
    end

    test "positions keyed by LIS id with normalized options", %{vote: vote} do
      by_id = Map.new(vote.positions, &{elem(&1.person, 1), &1})
      assert Enum.all?(vote.positions, &match?({"lis", _}, &1.person))
      assert %{option: "yea", raw_option: "Yea", raw_label: "Alsobrooks (D-MD)"} = by_id["S428"]
      assert by_id["S275"].option == "nay"
      assert by_id["S288"].option == "present"
      assert %{option: "absent", raw_option: "Not Voting"} = by_id["S348"]
    end
  end

  test "a nomination vote has no bill" do
    vote = SenateVote.vote(read("vote_119_1_nomination.xml"), source())
    assert vote.bill_external_id == nil
    assert vote.external_id == "senate-119-1-5"
    assert vote.voted_at == ~U[2025-01-09 22:30:00Z]
  end

  test "Guilty and Not Guilty map to yea and nay" do
    xml =
      read("vote_119_1_nomination.xml")
      |> String.replace("<vote_cast>Nay</vote_cast>", "<vote_cast>Not Guilty</vote_cast>")
      |> String.replace("<vote_cast>Yea</vote_cast>", "<vote_cast>Guilty</vote_cast>")

    assert [%{option: "nay"}, %{option: "yea"}] = SenateVote.vote(xml, source()).positions
  end
end
