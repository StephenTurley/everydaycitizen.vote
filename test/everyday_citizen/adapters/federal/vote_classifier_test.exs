defmodule EverydayCitizen.Adapters.Federal.VoteClassifierTest do
  use ExUnit.Case, async: true

  alias EverydayCitizen.Adapters.Federal.VoteClassifier

  @table [
    {"On Passage", "passage"},
    {"On Motion to Suspend the Rules and Pass", "passage"},
    {"On Motion to Suspend the Rules and Agree", "passage"},
    {"On Passage of the Bill", "passage"},
    {"On the Joint Resolution", "passage"},
    {"On Agreeing to the Resolution", "passage"},
    {"On the Conference Report", "passage"},
    {"On Overriding the Veto", "passage"},
    {"On the Cloture Motion", "cloture"},
    {"On the Nomination", "nomination"},
    {"On Agreeing to the Amendment", "amendment"},
    {"On the Amendment", "amendment"},
    {"On the Motion to Proceed", "procedural"},
    {"On Ordering the Previous Question", "procedural"},
    {"On Motion to Recommit", "procedural"},
    {"On the Motion to Table the Amendment", "procedural"},
    {"On the Motion (Motion to Discharge)", "procedural"},
    {"On the Decision of the Chair", "procedural"},
    {"Election of the Speaker", "other"},
    {nil, "other"}
  ]

  for {question, expected} <- @table do
    test "#{inspect(question)} -> #{expected}" do
      assert VoteClassifier.classify(unquote(question)) == unquote(expected)
    end
  end
end
