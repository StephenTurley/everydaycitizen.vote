defmodule EverydayCitizen.Adapters.Federal.States do
  @moduledoc """
  The states, the District of Columbia and the territories that send members to
  Congress, as `{postal code, name, possessive name}`.
  """

  @names [
    {"AL", "Alabama"},
    {"AK", "Alaska"},
    {"AS", "American Samoa"},
    {"AZ", "Arizona"},
    {"AR", "Arkansas"},
    {"CA", "California"},
    {"CO", "Colorado"},
    {"CT", "Connecticut"},
    {"DE", "Delaware"},
    {"DC", "District of Columbia"},
    {"FL", "Florida"},
    {"GA", "Georgia"},
    {"GU", "Guam"},
    {"HI", "Hawaii"},
    {"ID", "Idaho"},
    {"IL", "Illinois"},
    {"IN", "Indiana"},
    {"IA", "Iowa"},
    {"KS", "Kansas"},
    {"KY", "Kentucky"},
    {"LA", "Louisiana"},
    {"ME", "Maine"},
    {"MD", "Maryland"},
    {"MA", "Massachusetts"},
    {"MI", "Michigan"},
    {"MN", "Minnesota"},
    {"MS", "Mississippi"},
    {"MO", "Missouri"},
    {"MT", "Montana"},
    {"NE", "Nebraska"},
    {"NV", "Nevada"},
    {"NH", "New Hampshire"},
    {"NJ", "New Jersey"},
    {"NM", "New Mexico"},
    {"NY", "New York"},
    {"NC", "North Carolina"},
    {"ND", "North Dakota"},
    {"MP", "Northern Mariana Islands"},
    {"OH", "Ohio"},
    {"OK", "Oklahoma"},
    {"OR", "Oregon"},
    {"PA", "Pennsylvania"},
    {"PR", "Puerto Rico"},
    {"RI", "Rhode Island"},
    {"SC", "South Carolina"},
    {"SD", "South Dakota"},
    {"TN", "Tennessee"},
    {"TX", "Texas"},
    {"UT", "Utah"},
    {"VT", "Vermont"},
    {"VI", "U.S. Virgin Islands"},
    {"VA", "Virginia"},
    {"WA", "Washington"},
    {"WV", "West Virginia"},
    {"WI", "Wisconsin"},
    {"WY", "Wyoming"}
  ]

  @states for {code, name} <- @names, do: {code, name, name <> "'s"}

  @doc "Every entry, as `{code, name, possessive}`."
  @spec all() :: [{String.t(), String.t(), String.t()}]
  def all, do: @states

  @doc "The entry for a postal code, or nil."
  @spec by_code(String.t()) :: {String.t(), String.t(), String.t()} | nil
  def by_code(code), do: Enum.find(@states, &(elem(&1, 0) == code))

  @doc "The entry for a full name in any case, or nil."
  @spec by_name(String.t()) :: {String.t(), String.t(), String.t()} | nil
  def by_name(name) do
    wanted = String.downcase(name)
    Enum.find(@states, &(String.downcase(elem(&1, 1)) == wanted))
  end
end
