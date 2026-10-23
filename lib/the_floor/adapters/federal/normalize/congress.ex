defmodule TheFloor.Adapters.Federal.Normalize.Congress do
  @moduledoc """
  Normalizes a Congress.gov `/congress/{n}` response into the jurisdiction,
  legislature and chamber bodies, and the congress session with its
  per-session sub-sessions (`119-1`, `119-2`), in dependency order.
  """
  alias TheFloor.Ingest.Records.{Body, Jurisdiction, LegislativeSession, SourceRef}

  @jurisdiction "federal"

  @spec records(map(), SourceRef.t()) :: [struct()]
  def records(%{"congress" => congress}, %SourceRef{} = source) do
    number = to_string(congress["number"])
    subs = sub_sessions(congress["sessions"] || [])

    parent = %{
      name: congress["name"],
      start_date: subs |> Enum.map(& &1.start_date) |> min_date(),
      end_date: parent_end(subs)
    }

    [
      %Jurisdiction{
        key: @jurisdiction,
        name: "United States Congress",
        classification: "federal",
        source: source
      },
      body("congress", "United States Congress", "legislature", nil, source),
      body("house", "House of Representatives", "chamber", "congress", source),
      body("senate", "Senate", "chamber", "congress", source),
      session(number, nil, parent, source)
      | Enum.map(subs, &session("#{number}-#{&1.number}", number, &1, source))
    ]
  end

  defp body(external_id, name, classification, parent, source) do
    %Body{
      jurisdiction: @jurisdiction,
      external_id: external_id,
      name: name,
      classification: classification,
      parent_external_id: parent,
      source: source
    }
  end

  defp session(identifier, parent, attrs, source) do
    %LegislativeSession{
      jurisdiction: @jurisdiction,
      identifier: identifier,
      parent_identifier: parent,
      name: attrs[:name],
      start_date: attrs.start_date,
      end_date: attrs.end_date,
      source: source
    }
  end

  # Groups the per-chamber entries by session number: earliest start, latest end.
  defp sub_sessions(sessions) do
    sessions
    |> Enum.group_by(& &1["number"])
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {n, entries} ->
      %{
        number: n,
        start_date: entries |> Enum.map(&parse_date(&1["startDate"])) |> min_date(),
        end_date: entries |> Enum.map(&parse_date(&1["endDate"])) |> max_date()
      }
    end)
  end

  # The congress is open-ended while any session is still open.
  defp parent_end(subs) do
    ends = Enum.map(subs, & &1.end_date)
    if subs == [] or Enum.any?(ends, &is_nil/1), do: nil, else: max_date(ends)
  end

  defp parse_date(nil), do: nil
  defp parse_date(string), do: Date.from_iso8601!(string)

  defp min_date(dates), do: dates |> Enum.reject(&is_nil/1) |> Enum.min(Date, fn -> nil end)
  defp max_date(dates), do: dates |> Enum.reject(&is_nil/1) |> Enum.max(Date, fn -> nil end)
end
