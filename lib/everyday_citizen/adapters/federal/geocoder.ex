defmodule EverydayCitizen.Adapters.Federal.Geocoder do
  @moduledoc """
  The federal `EverydayCitizen.Reps.Locator`: an address to its state's Senate seats and
  its House district, from the Census Geocoder. The geography vintage is chosen
  per congress (`config :everyday_citizen, :federal, census_vintages: %{119 => …}`),
  because the current vintage already carries the next congress's districts and
  several states redrew theirs. District codes `00` and `98` (at large, delegate)
  are stored as `"ST-AL"`.
  """
  @behaviour EverydayCitizen.Reps.Locator

  alias EverydayCitizen.Adapters.Federal.HTTP

  @url "https://geocoding.geo.census.gov/geocoder/geographies/onelineaddress"

  @impl true
  def locate(address) do
    congress = Application.fetch_env!(:everyday_citizen, :federal)[:congress]
    vintage = Application.fetch_env!(:everyday_citizen, :federal)[:census_vintages][congress]

    params = [address: address, benchmark: "Public_AR_Current", vintage: vintage, format: "json"]

    # A person is waiting: one try with a short timeout, no shared rate limit.
    case HTTP.get(@url, params: params, req: [retry: false, receive_timeout: 5_000]) do
      {:ok, %{body: %{"result" => %{"addressMatches" => [match | _]}}}} ->
        district(match["geographies"], congress)

      {:ok, %{body: %{"result" => %{"addressMatches" => []}}}} ->
        {:error, :not_found}

      _ ->
        {:error, :unavailable}
    end
  rescue
    # never let a lookup crash: a crash report would carry the address
    _ -> {:error, :unavailable}
  end

  @impl true
  def districts_for(key) do
    case Regex.run(~r/^([A-Z]{2})-(AL|\d{1,2})$/, key) do
      [_, state, _] -> [{"senate", state}, {"house", key}]
      _ -> []
    end
  end

  # A missing layer means the service changed (vintage, layer name): unavailable,
  # not "we couldn't find that address". `ZZ` marks an area with no district.
  defp district(geographies, congress) do
    with {:ok, state} <- state(geographies["States"]),
         {:ok, geoid} <- layer(geographies["#{congress}th Congressional Districts"]),
         {:ok, code} <- code(String.slice(geoid, 2, 2)) do
      key = "#{state}-#{code}"
      {:ok, key, districts_for(key)}
    end
  end

  defp state([%{"STUSAB" => state} | _]), do: {:ok, state}
  defp state(_), do: {:error, :unavailable}

  defp layer([%{"GEOID" => geoid} | _]), do: {:ok, geoid}
  defp layer([]), do: {:error, :not_found}
  defp layer(_), do: {:error, :unavailable}

  defp code(cd) when cd in ["00", "98"], do: {:ok, "AL"}

  defp code(cd) do
    case Integer.parse(cd) do
      {n, ""} -> {:ok, Integer.to_string(n)}
      _ -> {:error, :not_found}
    end
  end
end
