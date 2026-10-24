defmodule TheFloor.Adapters.Federal.ActionClassifier do
  @moduledoc """
  Maps raw Congress.gov action text onto the normalized action types.

  Rules are evaluated in order and the first match wins. Matching is
  case-insensitive. Actions that match no rule return `nil`, and the caller
  keeps the raw text flagged as unclassified.
  """

  # `:skip` stops the search with no type: floor motions and cloture ("Motion to
  # proceed ... agreed to in Senate") are steps toward a vote, not passage.
  @rules [
    {~r/^(motion|cloture)\b/i, :skip},
    {~r/became public law|became private law/i, "became_law"},
    {~r/vetoed by president|pocket veto/i, "vetoed"},
    {~r/signed by president/i, "signed"},
    {~r/presented to president|enrolled bill signed|enrolled measure/i, "enrolled"},
    {~r/conference report|conferees/i, "conference"},
    {~r/^introduced in/i, "introduced"},
    {~r/^amendment .* agreed to|amendment \(.+\) agreed/i, "amended"},
    {~r/^passed\b|passed\/agreed to in|agreed to in (house|senate)|^resolution agreed to/i,
     "passed_chamber"},
    {~r/mark-?up|ordered to be reported/i, "markup"},
    {~r/^reported|reported by|reported \(amended\)/i, "reported"},
    {~r/hearings? held/i, "hearing"},
    {~r/referred to|read twice and referred/i, "referred"},
    {~r/placed on .* calendar/i, "scheduled"}
  ]

  @doc """
  Classifies an action map (`%{"text" => ..., "type" => ...}`) and returns the
  normalized type string, or `nil` when no rule matches.
  """
  @spec classify(%{optional(String.t()) => String.t() | nil}) :: String.t() | nil
  def classify(%{"text" => text}) when is_binary(text) do
    case Enum.find(@rules, fn {regex, _type} -> Regex.match?(regex, text) end) do
      {_regex, :skip} -> nil
      {_regex, type} -> type
      nil -> nil
    end
  end

  def classify(_action), do: nil
end
