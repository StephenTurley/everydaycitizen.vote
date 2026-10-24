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
end
