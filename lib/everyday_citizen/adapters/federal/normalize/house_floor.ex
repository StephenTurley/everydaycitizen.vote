defmodule EverydayCitizen.Adapters.Federal.Normalize.HouseFloor do
  @moduledoc """
  Normalizes the weekly floor-schedule XML from docs.house.gov
  (`floorschedule/category/floor-items/floor-item`) into floor `Records.Event`s.

  One event per top-level floor item (sub-items are supporting documents such as
  reports and prints, not floor business). Events are all-day on the week's Monday,
  midnight America/New_York in UTC. `legis-num` supplies the bill link: a label
  anywhere in it resolves (`"Senate amendments to H.R. 5334"` links H.R. 5334); a
  non-empty one that holds no bill label is kept as a raw label. An item with a
  `remove-date` is `status: "removed"`. Anything that is not a floor schedule
  parses to no events.
  """
  alias EverydayCitizen.Adapters.Federal.{BillId, VoteSupport}
  alias EverydayCitizen.Ingest.Records.{Event, SourceRef}

  @spec events(String.t(), SourceRef.t(), integer() | nil) :: [Event.t()]
  def events(xml, %SourceRef{} = source, default_congress \\ nil) when is_binary(xml) do
    case Saxy.SimpleForm.parse_string(xml) do
      {:ok, {"floorschedule", attrs, kids}} ->
        build(attrs, kids, source, default_congress)

      _ ->
        []
    end
  end

  defp build(attrs, kids, source, default_congress) do
    attrs = Map.new(attrs)

    with week when is_binary(week) <- attrs["week-date"],
         {:ok, date} <- Date.from_iso8601(week) do
      congress = parse_int(attrs["congress-num"]) || default_congress
      start_at = VoteSupport.eastern_to_utc(NaiveDateTime.new!(date, ~T[00:00:00]))

      kids
      |> items()
      |> Enum.map(&event(&1, week, start_at, congress, source))
      |> unique_ids()
    else
      _ -> []
    end
  end

  defp items(kids) do
    for {"category", _, cat_kids} <- kids,
        {"floor-items", _, item_kids} <- cat_kids,
        {"floor-item", _, _} = item <- item_kids,
        do: item
  end

  defp event({"floor-item", attrs, kids}, week, start_at, congress, source) do
    attrs = Map.new(attrs)
    label = kids |> child_text("legis-num") |> collapse()
    {linked, raw} = bills(label, congress)

    %Event{
      jurisdiction: "federal",
      body_external_id: "house",
      external_id: "house-floor-#{week}-#{slug(label, attrs["id"])}",
      classification: "floor",
      raw_classification: "floor-item",
      status: status(attrs["remove-date"]),
      title: kids |> child_text("floor-text") |> collapse() |> blank_to_nil(),
      start_at: start_at,
      all_day: true,
      bill_external_ids: linked,
      raw_bill_labels: raw,
      source: source
    }
  end

  defp bills("", _congress), do: {[], []}
  defp bills(_label, nil), do: {[], []}

  defp bills(label, congress) do
    case BillId.scan(label, congress) do
      [] -> {[], [label]}
      ids -> {ids, []}
    end
  end

  defp status(remove_date) when remove_date in [nil, ""], do: "scheduled"
  defp status(_remove_date), do: "removed"

  defp slug("", item_id), do: "item-#{item_id}"

  defp slug(label, _item_id) do
    label |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
  end

  # The same legis-num can be listed twice in a week; keep external ids unique.
  defp unique_ids(events) do
    {events, _seen} =
      Enum.map_reduce(events, %{}, fn event, seen ->
        n = Map.get(seen, event.external_id, 0)
        id = if n == 0, do: event.external_id, else: "#{event.external_id}-#{n + 1}"
        {%{event | external_id: id}, Map.put(seen, event.external_id, n + 1)}
      end)

    events
  end

  defp child_text(kids, name) do
    case Enum.find(kids, &match?({^name, _, _}, &1)) do
      {_, _, content} -> content |> Enum.filter(&is_binary/1) |> Enum.join()
      nil -> ""
    end
  end

  defp collapse(text), do: text |> String.split() |> Enum.join(" ")

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(text), do: text

  defp parse_int(nil), do: nil

  defp parse_int(string) do
    case Integer.parse(string) do
      {int, _} -> int
      :error -> nil
    end
  end
end
