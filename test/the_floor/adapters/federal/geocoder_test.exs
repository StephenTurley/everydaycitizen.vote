defmodule TheFloor.Adapters.Federal.GeocoderTest do
  use ExUnit.Case, async: true

  alias TheFloor.Adapters.Federal.Geocoder

  @dir "test/support/fixtures/federal/census"

  defp stub(status, file) do
    Req.Test.stub(TheFloor.Federal, fn conn ->
      send(self(), {:query, URI.decode_query(conn.query_string)})
      Plug.Conn.send_resp(conn, status, if(file, do: File.read!("#{@dir}/#{file}"), else: "busy"))
    end)
  end

  test "an address gives its state's Senate seat and its House district" do
    stub(200, "iowa_city.json")

    assert {:ok, "IA-1", [{"senate", "IA"}, {"house", "IA-1"}]} =
             Geocoder.locate("400 S Clinton St, Iowa City, IA 52240")

    assert_received {:query,
                     %{"vintage" => "ACS2025_Current", "benchmark" => "Public_AR_Current"}}
  end

  test "an at-large or delegate district is AL" do
    stub(200, "dc.json")

    assert {:ok, "DC-AL", [{"senate", "DC"}, {"house", "DC-AL"}]} =
             Geocoder.locate("1600 Pennsylvania Ave NW, Washington, DC 20500")
  end

  test "no match is not_found; a failing service is unavailable" do
    stub(200, "no_match.json")
    assert {:error, :not_found} = Geocoder.locate("99999 Nowhere Rd")

    stub(500, nil)
    assert {:error, :unavailable} = Geocoder.locate("400 S Clinton St")
  end

  test "a district key gives back its pairs" do
    assert Geocoder.districts_for("IA-1") == [{"senate", "IA"}, {"house", "IA-1"}]
    assert Geocoder.districts_for("DC-AL") == [{"senate", "DC"}, {"house", "DC-AL"}]
    assert Geocoder.districts_for("nonsense") == []
  end
end
