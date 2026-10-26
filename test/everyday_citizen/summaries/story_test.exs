defmodule EverydayCitizen.Summaries.StoryTest do
  use ExUnit.Case, async: true

  alias EverydayCitizen.Summaries.Story

  @sample """
  It warns members.

  ## Who this affects
  - Apps: send warnings.

  ## Words to know
  - Fraud ban: an ended account.

  ## For example
  Made-up situation: an app bans an account.

  ## If this becomes law
  - If you use a dating app: you'd be warned within a day.
  - If you run a dating app: you'd send the warnings.
  """

  test "splits the groups, the example and the rest" do
    story = Story.split(@sample)

    assert story.groups == [
             %{label: "If you use a dating app", sentence: "you'd be warned within a day."},
             %{label: "If you run a dating app", sentence: "you'd send the warnings."}
           ]

    assert story.example == "Made-up situation: an app bans an account."

    assert story.rest ==
             "It warns members.\n\n## Who this affects\n- Apps: send warnings.\n\n## Words to know\n- Fraud ban: an ended account."
  end

  test "a reply without the part has no groups and keeps its text" do
    text = "It does one thing.\n\n## Who this affects\n- People: x."
    assert %{groups: [], example: nil, rest: ^text} = Story.split(text)
  end

  test "lines without a label or a sentence are skipped, and at most four are kept" do
    lines = Enum.map_join(1..6, "\n", &"- G#{&1}: s#{&1}.")
    text = "S.\n\n## If this becomes law\n- No colon here\n- Empty:\n#{lines}"

    assert Enum.map(Story.split(text).groups, & &1.label) == ["G1", "G2", "G3", "G4"]
  end

  test "only the first colon splits" do
    text = "S.\n\n## If this becomes law\n- State officials: they could sue: in federal court."

    assert [%{label: "State officials", sentence: "they could sue: in federal court."}] =
             Story.split(text).groups
  end

  @tagged """
  It funds a program.

  ## If this becomes law
  - The Defense Department: it could be given up to $23 billion in 2026.

  ## Tags
  Spends or authorizes money · Made-up tag · Creates or changes a program · Sets rules

  ## Subjects
  - Missile defense program: SEC. 2, SEC. 3
  - Retirement savings: SEC. 401 through SEC. 450
  - Not a subject line
  """

  test "tags come back in order, only from the list, at most two" do
    assert Story.split(@tagged).tags == [
             "Spends or authorizes money",
             "Creates or changes a program"
           ]
  end

  test "subjects come with their section numbers, and the parts leave the rest" do
    story = Story.split(@tagged)

    assert story.subjects == [
             %{name: "Missile defense program", sections: ["2", "3"]},
             %{name: "Retirement savings", sections: ["401", "450"]}
           ]

    assert story.rest == "It funds a program."
  end

  test "a reply without tags or subjects has none" do
    assert %{tags: [], subjects: []} = Story.split("S.\n\n## Who this affects\n- P: x.")
  end

  test "the tag list is the thirteen of the design" do
    assert length(Story.tags()) == 13
    assert "Transfers land" in Story.tags()
  end

  test "tags written as a bullet are still read" do
    assert Story.split("S.\n\n## Tags\n- Sets rules · Changes taxes").tags == [
             "Sets rules",
             "Changes taxes"
           ]
  end

  test "checked lines replace the story's, and none removes the part" do
    text = "S.\n\n## If this becomes law\n- A: one.\n- B: two.\n\n## Tags\nSets rules"

    assert Story.put_groups(text, "- A: one, fixed.\nnot a line") ==
             "S.\n\n## If this becomes law\n- A: one, fixed.\n\n## Tags\nSets rules"

    assert Story.put_groups(text, "") == "S.\n\n## Tags\nSets rules"
    assert Story.put_groups("S.", "- A: x.") == "S."
  end

  test "a check keeps no more lines than it was sent" do
    text = "S.\n\n## If this becomes law\n- A: one."
    assert Story.put_groups(text, "- A: one.\n- B: invented.", 1) == text
  end
end
