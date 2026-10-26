defmodule EverydayCitizen.Adapters.Federal.Normalize.SenateFloor do
  @moduledoc """
  Normalizes the Congressional Record's Daily Digest "Next Meeting of the
  SENATE" page into one floor `Records.Event`: the meeting's time and date and,
  as its title, the "Program for <day>" text (what the Senate will take up).

  The page is preformatted text:

                         Next Meeting of the SENATE
                      10 a.m., Wednesday, September 23

                               Senate Chamber
      Program for Wednesday: Senate will continue consideration of ... S. 4668 ...

                Next Meeting of the HOUSE OF REPRESENTATIVES

  The date has no year: it is the first such date on or after the issue's date
  (so a January meeting named in a December issue is next year). A time that is
  not a clock time ("At the call of the Chair") makes an all-day event. Bills
  are found in the program by label (`BillId.scan/2`). A page without the
  heading gives nil.
  """
  alias EverydayCitizen.Adapters.Federal.{BillId, VoteSupport}
  alias EverydayCitizen.Ingest.Records.{Event, SourceRef}

  @months ~w(january february march april may june july august september october november december)
  @meeting ~r/Next Meeting of the SENATE\s*\n\s*(?<when>[^\n]*?),\s*(?<weekday>[A-Za-z]+),\s*(?<month>[A-Za-z]+)\s+(?<day>\d{1,2})\s*\n(?<rest>.*?)(?=Next Meeting of the HOUSE|_{5,}|<\/pre>|\z)/s
  @clock ~r/^(?<hour>\d{1,2})(?::(?<minute>\d{2}))?\s*(?<half>a\.m\.|p\.m\.|noon)$/i

  @spec event(String.t(), Date.t(), SourceRef.t(), integer()) :: Event.t() | nil
  def event(html, %Date{} = issue_date, %SourceRef{} = source, congress) do
    with %{"when" => time, "month" => month, "day" => day, "rest" => rest} <-
           Regex.named_captures(@meeting, html),
         {:ok, date} <- meeting_date(issue_date, month, day) do
      program = program(rest)
      clock = clock(String.trim(time))

      %Event{
        jurisdiction: "federal",
        body_external_id: "senate",
        external_id: "senate-floor-#{date}",
        classification: "floor",
        raw_classification: "record-next-meeting",
        title: if(program == "", do: nil, else: program),
        date: date,
        start_at: clock && VoteSupport.eastern_to_utc(NaiveDateTime.new!(date, clock)),
        bill_external_ids: BillId.scan(program, congress),
        source: source
      }
    else
      _ -> nil
    end
  end

  # the text after "Program for <day>:", on one line, without markup
  defp program(rest) do
    rest
    |> String.replace(~r/<[^>]*>/, "")
    |> String.replace("&amp;", "&")
    |> String.split(~r/Program for [A-Za-z]+:/, parts: 2)
    |> List.last()
    |> String.replace(~r/^\s*Senate Chamber\s*$/m, "")
    # a word hyphenated at a line end ("post-\ncloture") stays one word
    |> String.replace(~r/-\n\s*/, "-")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp meeting_date(issue_date, month, day) do
    with m when is_integer(m) <- Enum.find_index(@months, &(&1 == String.downcase(month))),
         {d, ""} <- Integer.parse(day),
         {:ok, date} <- Date.new(issue_date.year, m + 1, d) do
      if Date.before?(date, issue_date),
        do: Date.new(issue_date.year + 1, m + 1, d),
        else: {:ok, date}
    else
      _ -> :error
    end
  end

  defp clock(text) do
    case Regex.named_captures(@clock, text) do
      %{"half" => half} = c ->
        hour = String.to_integer(c["hour"])
        minute = if c["minute"] == "", do: 0, else: String.to_integer(c["minute"])
        Time.new!(hour24(hour, String.downcase(half)), minute, 0)

      nil ->
        nil
    end
  end

  defp hour24(12, "a.m."), do: 0
  defp hour24(12, _), do: 12
  defp hour24(hour, "p.m."), do: hour + 12
  defp hour24(hour, _), do: hour
end
