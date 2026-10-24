defmodule TheFloor.Reps do
  @moduledoc """
  A place's current representatives. The address is used once, to find the
  district, and is never stored; the district key is what pages and the session
  keep. The locator comes from the default jurisdiction's
  `config :the_floor, :locators` entry.
  """
  alias TheFloor.Legislature

  @type rep :: %{person: struct(), membership: struct(), body: struct()}

  @spec find(String.t()) :: {:ok, String.t(), [rep()]} | {:error, :not_found | :unavailable}
  def find(address) do
    with {:ok, key, seats} <- locator().locate(address) do
      {:ok, key, Legislature.current_members(jurisdiction(), seats, Date.utc_today())}
    end
  end

  @spec for_district(String.t()) :: [rep()]
  def for_district(key) do
    Legislature.current_members(jurisdiction(), locator().districts_for(key), Date.utc_today())
  end

  @doc "District keys a postal code falls in, largest share first; `[]` when unknown."
  @spec districts_for_postal_code(String.t()) :: [String.t()]
  def districts_for_postal_code(code), do: Legislature.postal_districts(jurisdiction(), code)

  @doc "True when the district key names a place the locator knows."
  @spec known_district?(String.t()) :: boolean()
  def known_district?(key), do: locator().districts_for(key) != []

  @doc "The default jurisdiction's key, for pages that show one jurisdiction."
  @spec jurisdiction() :: String.t()
  def jurisdiction, do: Application.fetch_env!(:the_floor, :default_jurisdiction)

  defp locator, do: Map.fetch!(Application.fetch_env!(:the_floor, :locators), jurisdiction())
end
