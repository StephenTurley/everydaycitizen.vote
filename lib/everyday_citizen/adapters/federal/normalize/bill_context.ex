defmodule EverydayCitizen.Adapters.Federal.Normalize.BillContext do
  @moduledoc """
  Normalizes a bill's committee steps, related measures and amendments from
  Congress.gov (`/bill/.../committees`, `/relatedbills`, `/amendments`), which
  together say what produced each version of its text.

    * Committee activities ("Referred To", "Markup By", "Reported By") become
      referred / markup / reported (anything else: other), dated in Eastern time,
      the committee (and subcommittees) named by system code.
    * A related bill whose relationship includes "Procedurally related" (the
      rule it was taken up under) is `procedural`; others are `related`.
    * Amendments keep the official description (House) or purpose (Senate,
      from the detail fetched when `needs_detail?/1`), latest action and page.
  """
  alias EverydayCitizen.Adapters.Federal.BillId

  alias EverydayCitizen.Ingest.Records.{
    BillAmendments,
    BillCommittees,
    BillRelations,
    BillTitles,
    SourceRef
  }

  @site "https://www.congress.gov"
  @kinds %{"Referred To" => "referred", "Markup By" => "markup", "Reported By" => "reported"}

  @spec committees([map()], String.t(), SourceRef.t()) :: BillCommittees.t()
  def committees(items, bill_external_id, source) do
    activities =
      for committee <- items,
          unit <- [committee | committee["subcommittees"] || []],
          activity <- unit["activities"] || [],
          code = unit["systemCode"],
          is_binary(code) do
        %{
          body_external_id: code,
          kind: Map.get(@kinds, activity["name"], "other"),
          date: eastern_date(activity["date"])
        }
      end

    %BillCommittees{
      jurisdiction: "federal",
      bill_external_id: bill_external_id,
      activities: activities,
      source: source
    }
  end

  @spec relations([map()], String.t(), SourceRef.t()) :: BillRelations.t()
  def relations(items, bill_external_id, source) do
    relations =
      for item <- items,
          id = BillId.external_id(item["congress"], item["type"], item["number"]),
          is_binary(id) do
        types = Enum.map(item["relationshipDetails"] || [], &String.downcase(&1["type"] || ""))

        %{
          bill_external_id: id,
          kind: if("procedurally related" in types, do: "procedural", else: "related")
        }
      end

    %BillRelations{
      jurisdiction: "federal",
      bill_external_id: bill_external_id,
      relations: Enum.uniq(relations),
      source: source
    }
  end

  @doc """
  Titles (`/bill/.../titles`) by kind, checked in order: "for portions" is `part`,
  "Popular" `popular`, "Short Title" `short`, "Official Title" `official`. Display
  titles are dropped (the bill holds its own); duplicates are removed.
  """
  @spec titles([map()], String.t(), SourceRef.t()) :: BillTitles.t()
  def titles(items, bill_external_id, source) do
    titles =
      for item <- items,
          kind = title_kind(item["titleType"] || ""),
          kind != nil,
          title = item["title"],
          is_binary(title) do
        %{title: title, kind: kind}
      end

    %BillTitles{
      jurisdiction: "federal",
      bill_external_id: bill_external_id,
      titles: Enum.uniq(titles),
      source: source
    }
  end

  defp title_kind(type) do
    cond do
      type =~ "for portions" -> "part"
      type =~ "Popular" -> "popular"
      type =~ "Short Title" -> "short"
      type =~ "Official Title" -> "official"
      true -> nil
    end
  end

  @doc "Whether an amendment list item needs its detail: agreed to, with no description of its own."
  @spec needs_detail?(map()) :: boolean()
  def needs_detail?(item),
    do: blank?(item["description"]) and blank?(item["purpose"]) and agreed?(item)

  @doc "The key a fetched detail is filed under: type and number (\"SAMDT6835\")."
  @spec detail_key(map()) :: String.t()
  def detail_key(item), do: "#{item["type"]}#{item["number"]}"

  # "agreed to", "adopted", "considered as adopted", but not "not agreed to"
  defp agreed?(item) do
    text = get_in(item, ["latestAction", "text"]) || ""
    text =~ ~r/agreed to|adopted/i and not (text =~ ~r/not agreed to|not adopted/i)
  end

  @spec amendments([map()], %{String.t() => map()}, String.t(), SourceRef.t()) ::
          BillAmendments.t()
  def amendments(items, details, bill_external_id, source) do
    amendments =
      for %{"type" => type, "number" => number} = item <- items, type in ["HAMDT", "SAMDT"] do
        detail = Map.get(details, detail_key(item), %{})
        action = item["latestAction"] || %{}

        %{
          external_id: "#{item["congress"]}-#{String.downcase(type)}-#{number}",
          identifier: "#{if type == "HAMDT", do: "H.Amdt.", else: "S.Amdt."} #{number}",
          description:
            Enum.find(
              [item["description"], item["purpose"], detail["description"], detail["purpose"]],
              &(!blank?(&1))
            ),
          latest_action: action["text"],
          latest_action_date: date(action["actionDate"]),
          url:
            "#{@site}/amendment/#{ordinal(item["congress"])}-congress/#{if type == "HAMDT", do: "house", else: "senate"}-amendment/#{number}",
          agreed: agreed?(item)
        }
      end

    %BillAmendments{
      jurisdiction: "federal",
      bill_external_id: bill_external_id,
      amendments: amendments,
      source: source
    }
  end

  defp blank?(value), do: value in [nil, ""]

  # 119 → "119th", 121 → "121st", 122 → "122nd", 113 → "113th"
  defp ordinal(n) when is_integer(n) do
    suffix =
      cond do
        rem(n, 100) in 11..13 -> "th"
        rem(n, 10) == 1 -> "st"
        rem(n, 10) == 2 -> "nd"
        rem(n, 10) == 3 -> "rd"
        true -> "th"
      end

    "#{n}#{suffix}"
  end

  defp ordinal(n), do: n |> to_string() |> String.to_integer() |> ordinal()

  defp date(nil), do: nil

  defp date(text) do
    case Date.from_iso8601(String.slice(text, 0, 10)) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp eastern_date(nil), do: nil

  defp eastern_date(text) do
    case DateTime.from_iso8601(text) do
      {:ok, dt, _} -> dt |> DateTime.shift_zone!("America/New_York") |> DateTime.to_date()
      _ -> date(text)
    end
  end
end
