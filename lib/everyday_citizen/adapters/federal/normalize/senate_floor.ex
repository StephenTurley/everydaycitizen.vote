defmodule EverydayCitizen.Adapters.Federal.Normalize.SenateFloor do
  @moduledoc """
  Normalizes the senate.gov floor schedule page into floor `Records.Event`s.

  UNVERIFIED AGAINST THE LIVE PAGE: senate.gov answers 403 to this project's
  capture machine, so the parser was written against the page's published
  structure and a synthetic fixture. It is deliberately defensive.

  The page is walked in document order. A heading-like element (`h1`-`h6`, `dt`,
  `th`, `caption`, `strong`, `b`) whose whole text is a date such as
  `"Monday, October 19, 2026"` starts a day; all text up to the next such heading
  is that day's text. One event per day, all-day, midnight America/New_York in
  UTC, titled with the day's text. Bills are found in that text by label
  (`BillId.scan/2`); nominations and other items are ignored. If no dated
  heading is found the result is `[]` and a warning is logged; this never raises.
  """
  require Logger

  alias EverydayCitizen.Adapters.Federal.{BillId, VoteSupport}
  alias EverydayCitizen.Ingest.Records.{Event, SourceRef}

  @heading_tags ~w(h1 h2 h3 h4 h5 h6 dt th caption strong b)
  @skipped_tags ~w(script style head noscript template)
  @months ~w(january february march april may june july august september october november december)
  @date ~r/^(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday),?\s+([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})\.?$/i

  @spec events(String.t(), SourceRef.t(), integer()) :: [Event.t()]
  def events(html, %SourceRef{} = source, congress) when is_binary(html) do
    days = html |> tokens() |> group()

    if days == [] do
      Logger.warning("senate floor schedule: no dated headings found; parser output is empty")
    end

    Enum.map(days, fn {date, text} -> event(date, text, congress, source) end)
  rescue
    exception ->
      Logger.warning("senate floor schedule: parse failed: #{Exception.message(exception)}")
      []
  end

  defp event(date, text, congress, source) do
    %Event{
      jurisdiction: "federal",
      body_external_id: "senate",
      external_id: "senate-floor-#{date}",
      classification: "floor",
      raw_classification: "floor-schedule",
      title: if(text == "", do: nil, else: text),
      start_at: VoteSupport.eastern_to_utc(NaiveDateTime.new!(date, ~T[00:00:00])),
      all_day: true,
      bill_external_ids: BillId.scan(text, congress),
      source: source
    }
  end

  # Document-order stream of {:day, date} and {:text, binary}.
  defp tokens(""), do: []

  defp tokens(html) do
    html |> LazyHTML.from_document() |> LazyHTML.to_tree() |> walk([])
  end

  defp walk(nodes, acc) when is_list(nodes), do: Enum.reduce(nodes, acc, &walk/2)
  defp walk(text, acc) when is_binary(text), do: [{:text, text} | acc]
  defp walk({:comment, _}, acc), do: acc
  defp walk({tag, _attrs, _kids}, acc) when tag in @skipped_tags, do: acc

  defp walk({tag, _attrs, kids} = node, acc) when tag in @heading_tags do
    case parse_day(node) do
      nil -> walk(kids, acc)
      date -> [{:day, date} | acc]
    end
  end

  defp walk({_tag, _attrs, kids}, acc), do: walk(kids, acc)
  defp walk(_other, acc), do: acc

  defp group(reversed_tokens) do
    {days, _current} =
      reversed_tokens
      |> Enum.reverse()
      |> Enum.reduce({[], nil}, fn
        {:day, date}, {days, _current} -> {add_day(days, date), date}
        {:text, _text}, {days, nil} -> {days, nil}
        {:text, text}, {days, date} -> {append(days, date, text), date}
      end)

    days |> Enum.reverse() |> Enum.map(fn {date, parts} -> {date, join(parts)} end)
  end

  defp add_day(days, date) do
    if List.keymember?(days, date, 0), do: days, else: [{date, []} | days]
  end

  defp append(days, date, text) do
    List.keyreplace(days, date, 0, {date, [text | elem(List.keyfind(days, date, 0), 1)]})
  end

  defp join(parts),
    do: parts |> Enum.reverse() |> Enum.join(" ") |> String.split() |> Enum.join(" ")

  defp parse_day(node) do
    text = node |> node_text() |> String.split() |> Enum.join(" ")

    with [_, month, day, year] <- Regex.run(@date, text),
         index when is_integer(index) <- Enum.find_index(@months, &(&1 == String.downcase(month))),
         {:ok, date} <- Date.new(String.to_integer(year), index + 1, String.to_integer(day)) do
      date
    else
      _ -> nil
    end
  end

  defp node_text(text) when is_binary(text), do: text
  defp node_text({:comment, _}), do: ""
  defp node_text({_tag, _attrs, kids}), do: Enum.map_join(kids, " ", &node_text/1)
end
