defmodule TheFloor.Adapters.Federal.Geocoder do
  @moduledoc """
  The federal `TheFloor.Reps.Locator`: an address to its state's Senate seats and
  its House district, from the Census Geocoder. The geography vintage is chosen
  per congress (`config :the_floor, :federal, census_vintages: %{119 => …}`),
  because the current vintage already carries the next congress's districts and
  several states redrew theirs. District codes `00` and `98` (at large, delegate)
  are stored as `"ST-AL"`.
  """
  @behaviour TheFloor.Reps.Locator

  alias TheFloor.Adapters.Federal.HTTP

  @url "https://geocoding.geo.census.gov/geocoder/geographies/onelineaddress"

  @impl true
  def locate(address) do
    congress = Application.fetch_env!(:the_floor, :federal)[:congress]
    vintage = Application.fetch_env!(:the_floor, :federal)[:census_vintages][congress]

    params = [address: address, benchmark: "Public_AR_Current", vintage: vintage, format: "json"]

    case HTTP.get(@url, params: params, limiter: :census) do
      {:ok, %{body: %{"result" => %{"addressMatches" => [match | _]}}}} ->
        district(match["geographies"], congress)

      {:ok, %{body: %{"result" => %{"addressMatches" => []}}}} ->
        {:error, :not_found}

      _ ->
        {:error, :unavailable}
    end
  end

  @impl true
  def districts_for(key) do
    case Regex.run(~r/^([A-Z]{2})-(AL|\d{1,2})$/, key) do
      [_, state, _] -> [{"senate", state}, {"house", key}]
      _ -> []
    end
  end

  defp district(geographies, congress) do
    with [%{"STUSAB" => state} | _] <- geographies["States"],
         [%{"GEOID" => geoid} | _] <- geographies["#{congress}th Congressional Districts"] do
      key = "#{state}-#{code(String.slice(geoid, 2, 2))}"
      {:ok, key, districts_for(key)}
    else
      _ -> {:error, :not_found}
    end
  end

  defp code(cd) when cd in ["00", "98"], do: "AL"
  defp code(cd), do: cd |> String.to_integer() |> Integer.to_string()
end
