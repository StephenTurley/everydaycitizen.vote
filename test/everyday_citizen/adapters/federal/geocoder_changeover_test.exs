defmodule EverydayCitizen.Adapters.Federal.GeocoderChangeoverTest do
  # changes the :federal config's date
  use ExUnit.Case, async: false

  import EverydayCitizen.FederalDate

  alias EverydayCitizen.Adapters.Federal.Geocoder

  @fixture "test/support/fixtures/federal/census/iowa_city.json"

  # Answers with the Iowa City match, its district layer renamed.
  defp stub(layer) do
    body = @fixture |> File.read!() |> String.replace("119th Congressional Districts", layer)

    Req.Test.stub(EverydayCitizen.Federal, fn conn ->
      send(self(), {:query, URI.decode_query(conn.query_string)})
      Plug.Conn.send_resp(conn, 200, body)
    end)
  end

  test "the district map is the sitting congress" do
    assert Geocoder.district_map() == "119"
  end

  test "uses the next congress's map once it sits" do
    on(~D[2027-01-10])
    stub("120th Congressional Districts")

    assert {:ok, "IA-1", _} = Geocoder.locate("400 S Clinton St, Iowa City, IA 52240")
    assert_received {:query, %{"vintage" => "ACS2026_Current"}}
    assert Geocoder.district_map() == "120"
  end

  test "the 121st congress's layer name" do
    on(~D[2029-01-10])
    with_vintage(121, "ACS2028_Current")
    stub("121st Congressional Districts")

    assert {:ok, "IA-1", _} = Geocoder.locate("400 S Clinton St, Iowa City, IA 52240")
  end

  test "a congress with no map is unavailable" do
    on(~D[2031-01-10])
    stub("122nd Congressional Districts")

    assert {:error, :unavailable} = Geocoder.locate("400 S Clinton St, Iowa City, IA 52240")
    refute_received {:query, _}
  end
end
