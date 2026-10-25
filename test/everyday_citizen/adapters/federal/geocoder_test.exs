defmodule EverydayCitizen.Adapters.Federal.GeocoderTest do
  use ExUnit.Case, async: true

  alias EverydayCitizen.Adapters.Federal.Geocoder

  @dir "test/support/fixtures/federal/census"

  defp stub(status, file) do
    Req.Test.stub(EverydayCitizen.Federal, fn conn ->
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

  test "an area with no congressional district (code ZZ) is not_found, not a crash" do
    body =
      "#{@dir}/iowa_city.json"
      |> File.read!()
      |> String.replace(~s("GEOID":"1901"), ~s("GEOID":"19ZZ"))

    Req.Test.stub(EverydayCitizen.Federal, fn conn -> Plug.Conn.send_resp(conn, 200, body) end)
    assert {:error, :not_found} = Geocoder.locate("somewhere")
  end

  test "a missing district layer means the service changed: unavailable, not not_found" do
    body =
      "#{@dir}/iowa_city.json"
      |> File.read!()
      |> String.replace("119th Congressional Districts", "Other")

    Req.Test.stub(EverydayCitizen.Federal, fn conn -> Plug.Conn.send_resp(conn, 200, body) end)
    assert {:error, :unavailable} = Geocoder.locate("somewhere")
  end

  test "a failing service is asked once, not retried, so visitors are not kept waiting" do
    test_pid = self()

    Req.Test.stub(EverydayCitizen.Federal, fn conn ->
      send(test_pid, :asked)
      Plug.Conn.send_resp(conn, 503, "busy")
    end)

    assert {:error, :unavailable} = Geocoder.locate("400 S Clinton St")
    assert_received :asked
    refute_received :asked
  end

  test "place matches full state names in any case and postal codes only in capitals" do
    assert {:ok,
            %{name: "Ohio", seats: [{"senate", {:exact, "OH"}}, {"house", {:prefix, "OH-"}}]}} =
             Geocoder.place("ohio")

    assert {:ok, %{name: "Ohio"}} = Geocoder.place("OH")
    for q <- ["in", "or", "me", "ok", "hi", "oh"], do: assert(Geocoder.place(q) == :error, q)
    assert {:ok, %{name: "Indiana"}} = Geocoder.place("IN")

    assert {:ok, %{name: "District of Columbia", seats: [{"house", {:prefix, "DC-"}}]}} =
             Geocoder.place("district of columbia")
  end

  test "district labels" do
    assert Geocoder.district_label("OH-4") == "Ohio's 4th district"
    assert Geocoder.district_label("NY-12") == "New York's 12th district"
    assert Geocoder.district_label("TX-22") == "Texas's 22nd district"
    assert Geocoder.district_label("CA-21") == "California's 21st district"
    assert Geocoder.district_label("CA-13") == "California's 13th district"
    assert Geocoder.district_label("CA-3") == "California's 3rd district"
    assert Geocoder.district_label("AK-AL") == "Alaska at large"
    assert Geocoder.district_label("IA") == "Iowa"
    assert Geocoder.district_label("ZZ-9") == "ZZ-9"
    assert Geocoder.district_label("nonsense") == "nonsense"
  end
end
