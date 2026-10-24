defmodule EverydayCitizen.Adapters.Federal.Normalize.VoteSubjectsTest do
  use ExUnit.Case, async: true

  alias EverydayCitizen.Adapters.Federal.Normalize.VoteSubjects

  @dir "test/support/fixtures/federal/congress_gov"

  defp json(name), do: @dir |> Path.join(name) |> File.read!() |> Jason.decode!()
  defp nominations, do: VoteSubjects.by_citation(json("nomination_list.json")["nominations"])

  describe "nomination_link/3" do
    test "an unpartitioned nomination links its page" do
      assert VoteSubjects.nomination_link(
               "PN1078",
               "Todd Blanche, of Florida, to be Attorney General",
               nominations()
             ) ==
               {"PN1078", "https://www.congress.gov/nomination/119th-congress/1078"}
    end

    test "a run-on part number is split by finding the nominee's name in the official record" do
      assert VoteSubjects.nomination_link(
               "PN10933",
               "Matthew R. Byrne, of Ohio, to be United States District Judge",
               nominations()
             ) ==
               {"PN1093-3", "https://www.congress.gov/nomination/119th-congress/1093/3"}

      # the official title is longer ("Ambassador Extraordinary and Plenipotentiary"); the name matches
      assert {"PN25-20", "https://www.congress.gov/nomination/119th-congress/25/20"} =
               VoteSubjects.nomination_link(
                 "PN2520",
                 "Mike Huckabee, of Arkansas, to be Ambassador to the State of Israel",
                 nominations()
               )
    end

    test "a reference whose candidates name someone else is left unlinked" do
      # PN730-11 is John Breslow, not Francis Brooke
      assert VoteSubjects.nomination_link(
               "PN73011",
               "Francis Brooke, of Virginia, to be Deputy Secretary of the Treasury",
               nominations()
             ) == nil
    end

    test "a record without a description is never matched" do
      assert VoteSubjects.nomination_link("PN252", "Scott Mayer, of Pennsylvania", nominations()) ==
               nil
    end
  end

  test "amendment_rolls/2 maps each recorded vote (session, roll) to its amendment" do
    rolls =
      VoteSubjects.amendment_rolls(json("bill_119_s_4668_amendments.json")["amendments"], 119)

    assert rolls[{2, 249}] ==
             {"SAMDT6835",
              "https://www.congress.gov/amendment/119th-congress/senate-amendment/6835"}

    assert rolls[{2, 242}] |> elem(0) == "SAMDT6776"
    assert map_size(rolls) == 6
  end
end
