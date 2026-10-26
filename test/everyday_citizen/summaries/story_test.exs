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
end
