defmodule EverydayCitizen.Reps.Locator do
  @moduledoc """
  Turns an address into the seats that represent it, for one jurisdiction
  (`config :everyday_citizen, :locators`). A seat is a body and the district its members
  are stored under; the district key names the place for URLs and the session.
  """

  @type seat :: {body_external_id :: String.t(), district :: String.t()}

  @callback locate(address :: String.t()) ::
              {:ok, district_key :: String.t(), [seat()]} | {:error, :not_found | :unavailable}

  @callback districts_for(district_key :: String.t()) :: [seat()]

  @typedoc "How a seat's district is matched: the whole key, or a key starting with a prefix."
  @type matcher :: {:exact | :prefix, String.t()}

  @doc """
  The place a typed query names (a state, say), with the seats of its
  members in the order they are listed.
  """
  @callback place(query :: String.t()) ::
              {:ok, %{name: String.t(), seats: [{body_external_id :: String.t(), matcher()}]}}
              | :error

  @doc "A district key in words, for display; an unknown key comes back as it is."
  @callback district_label(district :: String.t()) :: String.t()
end
