defmodule EverydayCitizen.PostalDistrictsTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Reps

  @src Records.SourceRef.new("https://x.test/postal-districts-test", "z")

  setup do
    {:ok, _} =
      Ingest.write(
        %Records.Jurisdiction{
          key: "federal",
          name: "F",
          classification: "federal",
          time_zone: "America/New_York",
          source: @src
        },
        nil
      )

    :ok
  end

  defp write!(rows) do
    {:ok, _} =
      Ingest.write(
        %Records.PostalDistricts{jurisdiction: "federal", rows: rows, source: @src},
        nil
      )
  end

  test "a ZIP code's districts, largest share first; unknown ZIPs have none" do
    write!([
      %{postal_code: "52031", district_key: "IA-2", land_share: 0.053},
      %{postal_code: "52031", district_key: "IA-1", land_share: 0.947},
      %{postal_code: "52240", district_key: "IA-1", land_share: 1.0}
    ])

    assert Reps.districts_for_postal_code("52031") == ["IA-1", "IA-2"]
    assert Reps.districts_for_postal_code("52240") == ["IA-1"]
    assert Reps.districts_for_postal_code("99999") == []
  end

  test "a new file replaces the whole set" do
    write!([%{postal_code: "52240", district_key: "IA-1", land_share: 1.0}])
    write!([%{postal_code: "52240", district_key: "IA-2", land_share: 1.0}])
    assert Reps.districts_for_postal_code("52240") == ["IA-2"]
  end
end
