defmodule EverydayCitizen.Adapters.Federal.VoteClassifier do
  @moduledoc """
  Maps a roll call's question onto the normalized vote types: `passage cloture
  amendment nomination procedural other`. Rules run in order, case-insensitive;
  procedural motions are checked before amendments so tabling an amendment is
  procedural.
  """

  @rules [
    {~r/cloture/i, "cloture"},
    {~r/nomination/i, "nomination"},
    {~r/motion to proceed|table|recommit|reconsider|discharge|previous question|quorum|adjourn|waive|point of order|instruct|decision of the chair/i,
     "procedural"},
    {~r/amendment/i, "amendment"},
    {~r/passage|suspend the rules|\bpass\b|on the bill|joint resolution|concurrent resolution|resolution|conference report|veto/i,
     "passage"}
  ]

  @spec classify(String.t() | nil) :: String.t()
  def classify(question) when is_binary(question) do
    Enum.find_value(@rules, "other", fn {regex, type} ->
      if Regex.match?(regex, question), do: type
    end)
  end

  def classify(_question), do: "other"
end
