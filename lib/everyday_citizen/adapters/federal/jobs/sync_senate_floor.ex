defmodule EverydayCitizen.Adapters.Federal.Jobs.SyncSenateFloor do
  @moduledoc """
  The Senate's next floor meeting, from the Congressional Record (senate.gov
  refuses automated requests). For each of the latest #{3} daily Record issues
  (Congress.gov API), finds the Daily Digest's "Next Meeting of the SENATE"
  article and writes its meeting as one floor event (`Normalize.SenateFloor`).
  The Record posts the morning after each session day, so the schedule is about
  a day behind the chamber's own; it runs three times a day to pick it up.
  Event ids are per meeting date, so reruns and overlapping issues update in
  place. API or page failures fail the job for retry.
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  require Logger

  alias EverydayCitizen.Adapters.Federal.{CongressGov, HTTP, Job}
  alias EverydayCitizen.Adapters.Federal.Normalize.SenateFloor

  @issues 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    congress = args["congress"] || Application.fetch_env!(:everyday_citizen, :federal)[:congress]

    Job.run("sync_senate_floor", fn run_id, _cursor -> sync(congress, run_id) end)
  end

  defp sync(congress, run_id) do
    with {:ok, %{"dailyCongressionalRecord" => issues}, _} <-
           CongressGov.get("/daily-congressional-record", limit: @issues),
         {:ok, events} <- events(issues, congress),
         :ok <- Job.write_events(events, run_id) do
      if events == [], do: Logger.warning("sync_senate_floor: no next-meeting article found")
      {:ok, %{items: length(events)}}
    end
  end

  # oldest issue first, so a newer issue's word on the same date wins
  defp events(issues, congress) do
    issues
    |> Enum.reverse()
    |> Enum.reduce_while({:ok, %{}}, fn issue, {:ok, by_id} ->
      case issue_event(issue, congress) do
        {:ok, nil} -> {:cont, {:ok, by_id}}
        {:ok, event} -> {:cont, {:ok, Map.put(by_id, event.external_id, event)}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, by_id} -> {:ok, Map.values(by_id)}
      error -> error
    end
  end

  defp issue_event(
         %{"volumeNumber" => volume, "issueNumber" => number, "issueDate" => at},
         congress
       ) do
    with {:ok, %{"articles" => articles}, _} <-
           CongressGov.get("/daily-congressional-record/#{volume}/#{number}/articles"),
         url when is_binary(url) <- next_meeting_url(articles),
         {:ok, %{raw: raw, source: source}} <- HTTP.get(url, limiter: :congress_gov, decode: :raw) do
      {:ok, SenateFloor.event(raw, issue_date(at), source, congress)}
    else
      nil -> {:ok, nil}
      error -> error
    end
  end

  defp next_meeting_url(articles) do
    articles
    |> Enum.flat_map(&(&1["sectionArticles"] || []))
    |> Enum.find(&((&1["title"] || "") =~ "Next Meeting of the SENATE"))
    |> case do
      nil -> nil
      article -> Enum.find_value(article["text"] || [], &formatted_text_url/1)
    end
  end

  defp formatted_text_url(%{"type" => "Formatted Text", "url" => url}), do: url
  defp formatted_text_url(_text), do: nil

  defp issue_date(at), do: at |> String.slice(0, 10) |> Date.from_iso8601!()
end
