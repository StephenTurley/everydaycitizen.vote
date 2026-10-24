defmodule EverydayCitizen.Adapters.Federal.Normalize.SenateVoteviewTest do
  use ExUnit.Case, async: true

  alias EverydayCitizen.Adapters.Federal.Normalize.SenateVoteview
  alias EverydayCitizen.Ingest.Records.SourceRef

  @dir "test/support/fixtures/federal/voteview"
  @src SourceRef.new("https://voteview.com/static/data/out/votes/S119_votes.csv", "v")

  defp files do
    %{
      rollcalls: File.read!("#{@dir}/S119_rollcalls.csv"),
      votes: File.read!("#{@dir}/S119_votes.csv"),
      members: File.read!("#{@dir}/S119_members.csv")
    }
  end

  defp votes, do: Map.new(SenateVoteview.votes(files(), @src), &{&1.external_id, &1})

  test "rollcalls lists each vote's session and official Senate roll number" do
    assert SenateVoteview.rollcalls(files().rollcalls) == [
             %{session: 1, roll: 1, voteview_roll: 1},
             %{session: 1, roll: 2, voteview_roll: 2},
             %{session: 2, roll: 1, voteview_roll: 660}
           ]
  end

  test "a vote keeps the Senate's numbering, question, result and bill" do
    vote = votes()["senate-119-1-1"]

    assert vote.jurisdiction == "federal"
    assert vote.body_external_id == "senate"
    assert vote.session_identifier == "119-1"
    assert vote.identifier == "Roll Call 1"
    assert vote.question == "On the Cloture Motion"
    assert vote.result == "Cloture Motion Agreed to"
    assert vote.passed == true
    assert vote.bill_external_id == "119-s-5"
    assert vote.classification == "cloture"
    assert vote.source == @src
  end

  test "Voteview gives only a date, stored as midnight Eastern" do
    assert votes()["senate-119-1-1"].voted_at == ~U[2025-01-09 05:00:00Z]
  end

  test "positions are keyed by bioguide id and totals are counted from them" do
    vote = votes()["senate-119-1-1"]

    assert vote.counts == %{yea: 84, nay: 9, present: 0, absent: 6}
    assert length(vote.positions) == 99

    assert %{
             person: {"bioguide", "G000386"},
             raw_label: "GRASSLEY, Charles Ernest",
             option: "yea",
             raw_option: "Yea"
           } in vote.positions
  end

  test "session numbering restarts: Voteview roll 660 is Senate roll 1 of session 2" do
    vote = votes()["senate-119-2-1"]
    assert vote.session_identifier == "119-2"
    assert vote.question == "On the Nomination"
    # a nomination (PN121) is not a bill
    assert vote.bill_external_id == nil
    # what was voted on, and Voteview's nomination reference (its part number may be run on)
    assert vote.description == "Keith Bass, of Texas, to be an Assistant Secretary of Defense"
    assert vote.subject_ref == "PN121"
    assert vote.subject_url == nil
    assert vote.counts == %{yea: 50, nay: 35, present: 0, absent: 15}
  end

  test "cast codes map to options; not-a-member rows are dropped" do
    header = "congress,chamber,rollnumber,icpsr,cast_code,prob\n"

    rows =
      for {icpsr, code} <- [{"14226", "7"}, {"14226", "9"}, {"14226", "2"}, {"14226", "0"}],
          do: "119,Senate,1,#{icpsr},#{code},100.0\n"

    options =
      for code_rows <- rows do
        [vote | _] =
          SenateVoteview.votes(%{files() | votes: header <> code_rows}, @src)
          |> Enum.filter(&(&1.external_id == "senate-119-1-1"))

        Enum.map(vote.positions, &{&1.option, &1.raw_option})
      end

    assert options == [
             [{"present", "Present"}],
             [{"absent", "Not Voting"}],
             [{"absent", "Paired Yea"}],
             []
           ]
  end

  test "the President's announced position is not a senator's vote" do
    # Voteview's Senate vote file carries a row for the President (icpsr 99912).
    votes = files().votes <> "119,Senate,1,99912,1,100.0\n"
    [vote | _] = SenateVoteview.votes(%{files() | votes: votes}, @src)

    assert vote.external_id == "senate-119-1-1"
    assert vote.counts.yea == 84
    refute Enum.any?(vote.positions, &(&1.raw_label =~ "TRUMP"))
  end

  test "a tie the Vice President broke counts the VP's yea in the totals" do
    header = "congress,chamber,rollnumber,icpsr,cast_code,prob\n"
    # roll 2 ("Motion to Proceed Agreed to") as a 1-1 tie that passed
    tie = header <> "119,Senate,2,14226,1,100.0\n119,Senate,2,42102,6,100.0\n"

    vote =
      %{files() | votes: tie}
      |> SenateVoteview.votes(@src)
      |> Enum.find(&(&1.external_id == "senate-119-1-2"))

    assert vote.passed
    assert vote.counts == %{yea: 2, nay: 1, present: 0, absent: 0}
    assert length(vote.positions) == 2
  end
end
