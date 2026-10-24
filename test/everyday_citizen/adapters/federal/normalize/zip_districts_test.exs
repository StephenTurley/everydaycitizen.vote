defmodule EverydayCitizen.Adapters.Federal.Normalize.ZipDistrictsTest do
  use ExUnit.Case, async: true

  alias EverydayCitizen.Adapters.Federal.Normalize.ZipDistricts
  alias EverydayCitizen.Ingest.Records.{PostalDistricts, SourceRef}

  @file_text File.read!("test/support/fixtures/federal/census/cd119_zcta_sample.txt")
  @src SourceRef.new("https://www2.census.gov/x.txt", "x")

  test "each ZIP area's districts with their share of its land, keyed like the reps pages" do
    assert %PostalDistricts{jurisdiction: "federal", rows: rows, source: @src} =
             ZipDistricts.parse(@file_text, @src)

    by_zip =
      Enum.group_by(rows, & &1.postal_code, &{&1.district_key, Float.round(&1.land_share, 3)})

    assert by_zip["52240"] == [{"IA-1", 1.0}]
    assert Enum.sort(by_zip["52031"]) == [{"IA-1", 0.947}, {"IA-2", 0.053}]
    assert by_zip["20001"] == [{"DC-AL", 1.0}]
  end

  test "water with no ZIP area, and unassigned (ZZ) districts, are skipped" do
    rows = ZipDistricts.parse(@file_text, @src).rows
    assert Enum.all?(rows, &(&1.postal_code =~ ~r/^\d{5}$/))
    refute Enum.any?(rows, &(&1.postal_code == "06437"))
  end
end
