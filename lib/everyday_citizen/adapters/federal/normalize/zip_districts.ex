defmodule EverydayCitizen.Adapters.Federal.Normalize.ZipDistricts do
  @moduledoc """
  Parses Census's congressional district to ZIP Code Tabulation Area relationship
  file (pipe-delimited, BOM-prefixed) into `Records.PostalDistricts`: each ZIP
  area's districts, keyed like the reps pages (`"IA-1"`, `"DC-AL"`), with the
  share of the ZIP area's land in each. Rows with no ZIP area (water) and
  unassigned `ZZ` districts are skipped. ZIP areas approximate USPS ZIP codes.
  """
  alias EverydayCitizen.Ingest.Records.{PostalDistricts, SourceRef}

  @states %{
    "01" => "AL",
    "02" => "AK",
    "04" => "AZ",
    "05" => "AR",
    "06" => "CA",
    "08" => "CO",
    "09" => "CT",
    "10" => "DE",
    "11" => "DC",
    "12" => "FL",
    "13" => "GA",
    "15" => "HI",
    "16" => "ID",
    "17" => "IL",
    "18" => "IN",
    "19" => "IA",
    "20" => "KS",
    "21" => "KY",
    "22" => "LA",
    "23" => "ME",
    "24" => "MD",
    "25" => "MA",
    "26" => "MI",
    "27" => "MN",
    "28" => "MS",
    "29" => "MO",
    "30" => "MT",
    "31" => "NE",
    "32" => "NV",
    "33" => "NH",
    "34" => "NJ",
    "35" => "NM",
    "36" => "NY",
    "37" => "NC",
    "38" => "ND",
    "39" => "OH",
    "40" => "OK",
    "41" => "OR",
    "42" => "PA",
    "44" => "RI",
    "45" => "SC",
    "46" => "SD",
    "47" => "TN",
    "48" => "TX",
    "49" => "UT",
    "50" => "VT",
    "51" => "VA",
    "53" => "WA",
    "54" => "WV",
    "55" => "WI",
    "56" => "WY",
    "60" => "AS",
    "66" => "GU",
    "69" => "MP",
    "72" => "PR",
    "78" => "VI"
  }

  @spec parse(binary(), SourceRef.t()) :: PostalDistricts.t()
  def parse(text, %SourceRef{} = source) do
    [header | lines] =
      text |> String.replace_prefix("﻿", "") |> String.split(["\r\n", "\n"], trim: true)

    columns = String.split(header, "|")
    at = fn name -> Enum.find_index(columns, &(&1 == name)) end
    {cd, zcta, land} = {at.("GEOID_CD119_20"), at.("GEOID_ZCTA5_20"), at.("AREALAND_PART")}

    parts =
      for line <- lines,
          fields = String.split(line, "|"),
          zip = Enum.at(fields, zcta),
          zip =~ ~r/^\d{5}$/,
          {:ok, key} <- [district_key(Enum.at(fields, cd))],
          do: {zip, key, String.to_integer(Enum.at(fields, land) || "0")}

    rows =
      parts
      |> Enum.group_by(&elem(&1, 0))
      |> Enum.flat_map(fn {zip, zip_parts} -> shares(zip, zip_parts) end)

    %PostalDistricts{jurisdiction: "federal", rows: rows, source: source}
  end

  defp shares(zip, parts) do
    total = parts |> Enum.map(&elem(&1, 2)) |> Enum.sum()

    parts
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 2))
    |> Enum.map(fn {key, lands} ->
      share = if total > 0, do: Enum.sum(lands) / total, else: 1 / length(parts)
      %{postal_code: zip, district_key: key, land_share: share}
    end)
  end

  defp district_key(<<state::binary-size(2), cd::binary-size(2)>>) do
    with {:ok, st} <- Map.fetch(@states, state),
         {:ok, code} <- code(cd),
         do: {:ok, "#{st}-#{code}"}
  end

  defp district_key(_), do: :error

  defp code(cd) when cd in ["00", "98"], do: {:ok, "AL"}

  defp code(cd) do
    case Integer.parse(cd) do
      {n, ""} -> {:ok, Integer.to_string(n)}
      _ -> :error
    end
  end
end
