defmodule TheFloor.Adapters.Federal.Normalize.Bill do
  @moduledoc """
  Normalizes Congress.gov bill responses (detail, actions, cosponsors, subjects,
  text versions) into bill records. Each function takes the `SourceRef` of the
  response its input came from.
  """
  alias TheFloor.Adapters.Federal.{ActionClassifier, BillId}

  alias TheFloor.Ingest.Records.{
    Bill,
    BillAction,
    BillActions,
    BillSummaries,
    BillVersion,
    Sponsorships
  }

  alias TheFloor.Ingest.Records.SourceRef
  alias TheFloor.Ingest.SafeHtml

  @jurisdiction "federal"

  @doc "Builds the bill from a `/bill/{c}/{t}/{n}` response and a `/subjects` response."
  @spec bill(map(), map(), SourceRef.t()) :: Bill.t()
  def bill(%{"bill" => b}, subjects_json, %SourceRef{} = source) do
    external_id = BillId.external_id(b["congress"], b["type"], b["number"])

    %Bill{
      jurisdiction: @jurisdiction,
      session_identifier: to_string(b["congress"]),
      external_id: external_id,
      web_url: BillId.web_url(external_id),
      identifier: BillId.identifier(b["type"], b["number"]),
      classification: BillId.classification(b["type"]),
      title: b["title"],
      from_body_external_id: chamber(b["originChamberCode"]),
      introduced_on: date(b["introducedDate"]),
      updated_at_source: datetime(b["updateDate"]),
      subjects: subjects(subjects_json),
      source: source
    }
  end

  @doc "External id of the bill in a detail response."
  @spec external_id(map()) :: String.t()
  def external_id(%{"bill" => b}), do: BillId.external_id(b["congress"], b["type"], b["number"])

  @doc """
  Builds the action set from the `actions` list (Congress.gov returns newest
  first). Positions are 0-based, oldest first.
  """
  @spec actions([map()], String.t(), SourceRef.t()) :: BillActions.t()
  def actions(actions, bill_external_id, %SourceRef{} = source) do
    ordered =
      actions
      |> Enum.reverse()
      |> Enum.sort_by(&date(&1["actionDate"]), Date)
      |> Enum.with_index(&action/2)

    %BillActions{
      jurisdiction: @jurisdiction,
      bill_external_id: bill_external_id,
      actions: ordered,
      source: source
    }
  end

  @doc "Builds the sponsor (primary) plus cosponsor set."
  @spec sponsorships(map(), [map()], String.t(), SourceRef.t()) :: Sponsorships.t()
  def sponsorships(%{"bill" => b}, cosponsors, bill_external_id, %SourceRef{} = source) do
    primary =
      for %{"bioguideId" => id} <- b["sponsors"] || [] do
        %{
          person: {"bioguide", id},
          classification: "primary",
          date: date(b["introducedDate"]),
          withdrawn_on: nil
        }
      end

    others =
      for %{"bioguideId" => id} = c <- cosponsors do
        %{
          person: {"bioguide", id},
          classification: "cosponsor",
          date: date(c["sponsorshipDate"]),
          withdrawn_on: date(c["sponsorshipWithdrawnDate"])
        }
      end

    %Sponsorships{
      jurisdiction: @jurisdiction,
      bill_external_id: bill_external_id,
      sponsorships: primary ++ others,
      source: source
    }
  end

  @doc """
  Builds the bill's summary set from a `summaries` list (the API's `/summaries`
  response or a BILLSTATUS file's), sanitized and attributed to CRS.
  """
  @spec summaries([map()], String.t(), SourceRef.t()) :: BillSummaries.t()
  def summaries(summaries, bill_external_id, %SourceRef{} = source) do
    %BillSummaries{
      jurisdiction: @jurisdiction,
      bill_external_id: bill_external_id,
      author: "Congressional Research Service",
      summaries:
        summaries
        |> Enum.map(fn s ->
          %{
            version_code: s["versionCode"],
            action_date: date(s["actionDate"]),
            action_description: s["actionDesc"],
            html: SafeHtml.sanitize(s["text"] || ""),
            updated_at_source: datetime(s["updateDate"])
          }
        end)
        |> Enum.uniq_by(&{&1.version_code, &1.action_date}),
      source: source
    }
  end

  @doc "Builds version metadata from the `textVersions` list; entries without a package code are dropped."
  @spec versions([map()], String.t(), SourceRef.t()) :: [BillVersion.t()]
  def versions(text_versions, bill_external_id, %SourceRef{} = source) do
    # Bindings via a one-element generator: a bare `x = nil` in `for` is a
    # filter and would drop versions that lack one of the formats.
    for v <- text_versions,
        formats = Map.new(v["formats"] || [], &{&1["type"], &1["url"]}),
        {xml_url, text_url} <- [{formats["Formatted XML"], formats["Formatted Text"]}],
        code = code(xml_url || text_url),
        not is_nil(code) do
      %BillVersion{
        jurisdiction: @jurisdiction,
        bill_external_id: bill_external_id,
        code: code,
        classification: v["type"],
        date: datetime(v["date"]) && DateTime.to_date(datetime(v["date"])),
        xml_url: xml_url,
        text_url: text_url,
        source: source
      }
    end
  end

  defp action(a, position) do
    %BillAction{
      position: position,
      date: date(a["actionDate"]),
      description: a["text"],
      raw_type: a["type"],
      raw_code: a["actionCode"],
      classification: ActionClassifier.classify(%{"text" => a["text"], "type" => a["type"]}),
      actor_body_external_id: actor(a["sourceSystem"])
    }
  end

  defp actor(%{"name" => name}) when is_binary(name) do
    cond do
      name =~ ~r/house/i -> "house"
      name =~ ~r/senate/i -> "senate"
      true -> nil
    end
  end

  defp actor(_), do: nil

  defp chamber("H"), do: "house"
  defp chamber("S"), do: "senate"
  defp chamber(_), do: nil

  defp subjects(%{"subjects" => %{"legislativeSubjects" => list}}),
    do: Enum.map(list, & &1["name"])

  defp subjects(_), do: []

  # `BILLS-119hr22eh.xml` -> "eh"
  defp code(url) when is_binary(url) do
    case Regex.run(~r/BILLS-\d+[a-z]+\d+([a-z0-9]+)\.[a-z]+$/i, url) do
      [_, code] -> code
      _ -> nil
    end
  end

  defp code(_), do: nil

  defp date(nil), do: nil

  defp date(string) do
    case Date.from_iso8601(String.slice(string, 0, 10)) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp datetime(nil), do: nil

  defp datetime(string) do
    case DateTime.from_iso8601(string) do
      {:ok, dt, _} ->
        dt

      _ ->
        case Date.from_iso8601(string) do
          {:ok, d} -> DateTime.new!(d, ~T[00:00:00], "Etc/UTC")
          _ -> nil
        end
    end
  end
end
