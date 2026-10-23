defmodule TheFloor.Adapters.Federal.Coverage do
  @moduledoc """
  The federal coverage checks: each is `{name, expected_fun, actual_fun, tolerance}`.
  `expected_fun` asks the source (`{:ok, n} | {:error, reason}`); `actual_fun`
  counts what is stored. Tolerance is a fraction we may lag the source by.
  """
  alias TheFloor.Adapters.Federal.{CongressGov, Sessions, Voteview}
  alias TheFloor.Adapters.Federal.Normalize.SenateVoteview
  alias TheFloor.{Legislation, Legislature, Votes}

  @jurisdiction "federal"
  # Bills are introduced while a run is in progress.
  @bill_tolerance 0.005

  @type check ::
          {String.t(), (-> {:ok, integer()} | {:error, term()}), (-> integer()), number()}

  @spec checks(integer()) :: [check()]
  def checks(congress) do
    [bills(congress)] ++
      votes("house", congress) ++
      votes("senate", congress) ++ [senate_tallies(congress)] ++ members()
  end

  defp bills(congress) do
    {"bills:#{congress}", fn -> CongressGov.count("/bill/#{congress}") end,
     fn -> count_bills(congress) end, @bill_tolerance}
  end

  # With no stored child sessions there is nothing to compare per session; one
  # failed check per chamber keeps that from passing silently.
  defp votes(chamber, congress) do
    case Sessions.numbers(congress, nil) do
      [] ->
        [{"votes:#{chamber}", fn -> {:error, "no child sessions stored"} end, fn -> 0 end, 0}]

      sessions ->
        Enum.map(sessions, &session_votes(chamber, congress, &1))
    end
  end

  defp session_votes(chamber, congress, session) do
    {"votes:#{chamber}:#{congress}-#{session}", expected_votes(chamber, congress, session),
     fn -> count_votes(chamber, congress, session) end, 0}
  end

  defp expected_votes("house", congress, session) do
    fn -> CongressGov.count("/house-vote/#{congress}/#{session}") end
  end

  defp expected_votes("senate", congress, session) do
    fn ->
      with {:ok, csv} <- Voteview.rollcalls(congress) do
        {:ok, csv |> SenateVoteview.rollcalls() |> Enum.count(&(&1.session == session))}
      end
    end
  end

  # Senate votes come from Voteview, a third party; this checks them against an
  # official source. Senate bill actions print each roll call's tally
  # ("... by Yea-Nay Vote. 52 - 48. Record Vote Number: 123."), and every such roll
  # call must be stored with the same yea and nay totals. The tolerance absorbs a
  # vote recorded on a bill before Voteview has published it.
  @tally ~r/(\d+)\s*-\s*(\d+)\.\s*Record Vote Number:\s*(\d+)/
  @tally_tolerance 0.01

  defp senate_tallies(congress) do
    {"votes:senate:tallies", fn -> {:ok, map_size(recorded_tallies(congress))} end,
     fn -> matching_tallies(congress) end, @tally_tolerance}
  end

  defp matching_tallies(congress) do
    recorded = recorded_tallies(congress)
    stored = recorded |> Map.keys() |> Votes.tallies()
    Enum.count(recorded, fn {id, tally} -> stored[id] == tally end)
  end

  # `%{vote external id => {yea, nay}}` from the Senate tallies in bill actions.
  defp recorded_tallies(congress) do
    starts =
      @jurisdiction
      |> Legislature.child_sessions("#{congress}")
      |> Enum.filter(& &1.start_date)
      |> Enum.sort_by(& &1.start_date, {:desc, Date})

    for {date, text} <-
          Legislation.actions_containing(@jurisdiction, "#{congress}", "Record Vote Number"),
        [_, yea, nay, roll] <- [Regex.run(@tally, text)],
        %{identifier: session} <- [
          date && Enum.find(starts, &(Date.compare(&1.start_date, date) != :gt))
        ],
        into: %{} do
      {"senate-#{session}-#{roll}", {String.to_integer(yea), String.to_integer(nay)}}
    end
  end

  defp members do
    for chamber <- ["house", "senate"] do
      {"members:#{chamber}", fn -> expected_members(chamber) end,
       fn -> count_members(chamber) end, 0}
    end
  end

  # Current members by the chamber of their most recent term.
  defp expected_members(chamber) do
    count =
      "/member/congress/#{congress()}"
      |> CongressGov.paginate("members", currentMember: true)
      |> Enum.count(fn {member, _source} -> latest_chamber(member) == chamber end)

    {:ok, count}
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  defp latest_chamber(%{"terms" => terms}) do
    terms
    |> terms_list()
    |> Enum.max_by(&(&1["startYear"] || 0), fn -> %{} end)
    |> Map.get("chamber", "")
    |> then(fn name -> if name =~ "Senate", do: "senate", else: "house" end)
  end

  defp latest_chamber(_), do: nil

  defp terms_list(%{"item" => items}) when is_list(items), do: items
  defp terms_list(items) when is_list(items), do: items
  defp terms_list(_), do: []

  defp congress, do: Application.fetch_env!(:the_floor, :federal)[:congress]

  defp count_bills(congress) do
    case Legislature.get_session(@jurisdiction, "#{congress}") do
      nil -> 0
      session -> Legislation.count_bills(session.id)
    end
  end

  defp count_votes(chamber, congress, session) do
    with %{} = body <- Legislature.get_body(@jurisdiction, chamber),
         %{} = stored <- Legislature.get_session(@jurisdiction, "#{congress}-#{session}") do
      Votes.count_votes(body.id, stored.id)
    else
      nil -> 0
    end
  end

  defp count_members(chamber) do
    case Legislature.get_body(@jurisdiction, chamber) do
      nil -> 0
      body -> body.id |> Legislature.current_memberships(Date.utc_today()) |> length()
    end
  end
end
