defmodule TheFloor.Adapters.Federal.Normalize.CommitteeMeeting do
  @moduledoc """
  Normalizes Congress.gov `committee-meeting` JSON (House and Senate) into a
  `Records.Event`.

  `event/2` reads one meeting detail document. A missing or unparseable `date`
  gives `start_at: nil`; the job skips such meetings.

  Type mapping: `Hearing`, `Open Hearing` and `Closed Hearing` are hearings,
  `Markup` is a markup, everything else (`Meeting`, `Open Business Meeting`, ...)
  is `other`; the raw type is always kept. `meetingStatus` is lowercased into
  `status` (`canceled`, `postponed`, `rescheduled`, ...). A joint meeting lists
  several committees; the first is the body. `body_external_id` is the committee
  `systemCode`; the job drops it when that committee is not stored.

  Only `relatedItems.bills` are linked; nominations and other item kinds are
  ignored. A bill whose type is not recognized is kept as a raw label.
  """
  alias TheFloor.Adapters.Federal.BillId
  alias TheFloor.Ingest.Records.{Event, SourceRef}

  @classifications %{
    "Hearing" => "hearing",
    "Open Hearing" => "hearing",
    "Closed Hearing" => "hearing",
    "Markup" => "markup"
  }

  @doc "External id of a committee meeting."
  @spec external_id(String.t()) :: String.t()
  def external_id(event_id), do: "meeting-#{event_id}"

  @spec event(map(), SourceRef.t()) :: Event.t()
  def event(%{"committeeMeeting" => meeting}, %SourceRef{} = source) do
    congress = meeting["congress"]
    {linked, raw} = bills(meeting, congress)
    type = meeting["type"]

    %Event{
      jurisdiction: "federal",
      body_external_id: body(meeting),
      external_id: external_id(meeting["eventId"]),
      classification: Map.get(@classifications, type, "other"),
      raw_classification: type,
      status: status(meeting["meetingStatus"]),
      title: meeting["title"],
      start_at: parse_datetime(meeting["date"]),
      location: location(meeting["location"]),
      bill_external_ids: linked,
      raw_bill_labels: raw,
      source: source
    }
  end

  defp body(%{"committees" => [%{"systemCode" => code} | _]}), do: code
  defp body(_meeting), do: nil

  defp status(nil), do: "scheduled"
  defp status(status), do: String.downcase(status)

  defp location(%{} = location) do
    case Enum.reject([location["building"], location["room"]], &(&1 in [nil, ""])) do
      [] -> nil
      parts -> Enum.join(parts, ", ")
    end
  end

  defp location(_), do: nil

  defp bills(meeting, congress) do
    meeting
    |> get_in(["relatedItems", "bills"])
    |> List.wrap()
    |> Enum.reduce({[], []}, fn bill, {linked, raw} ->
      label = "#{bill["type"]} #{bill["number"]}"

      case BillId.from_label(label, bill["congress"] || congress) do
        nil -> {linked, [label | raw]}
        id -> {[id | linked], raw}
      end
    end)
    |> then(fn {linked, raw} -> {Enum.reverse(linked), Enum.reverse(raw)} end)
  end

  defp parse_datetime(string) when is_binary(string) do
    case DateTime.from_iso8601(string) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil
end
