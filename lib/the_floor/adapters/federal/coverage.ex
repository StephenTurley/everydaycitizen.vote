defmodule TheFloor.Adapters.Federal.Coverage do
  @moduledoc """
  The federal coverage checks: each is `{name, expected_fun, actual_fun, tolerance}`.
  `expected_fun` asks the source (`{:ok, n} | {:error, reason}`); `actual_fun`
  counts what is stored. Tolerance is a fraction we may lag the source by.
  """
  alias TheFloor.Adapters.Federal.{CongressGov, HTTP, Sessions}
  alias TheFloor.Adapters.Federal.Jobs.SyncSenateVotes
  alias TheFloor.Adapters.Federal.Normalize.SenateVote
  alias TheFloor.{Legislation, Legislature, Votes}

  @jurisdiction "federal"
  # Bills are introduced while a run is in progress.
  @bill_tolerance 0.005

  @type check ::
          {String.t(), (-> {:ok, integer()} | {:error, term()}), (-> integer()), number()}

  @spec checks(integer()) :: [check()]
  def checks(congress) do
    [bills(congress)] ++ votes("house", congress) ++ votes("senate", congress) ++ members()
  end

  defp bills(congress) do
    {"bills:#{congress}", fn -> CongressGov.count("/bill/#{congress}") end,
     fn -> count_bills(congress) end, @bill_tolerance}
  end

  defp votes(chamber, congress) do
    for session <- Sessions.numbers(congress, nil) do
      {"votes:#{chamber}:#{congress}-#{session}", expected_votes(chamber, congress, session),
       fn -> count_votes(chamber, congress, session) end, 0}
    end
  end

  defp expected_votes("house", congress, session) do
    fn -> CongressGov.count("/house-vote/#{congress}/#{session}") end
  end

  defp expected_votes("senate", congress, session) do
    fn ->
      with {:ok, %{raw: raw}} <-
             HTTP.get(SyncSenateVotes.menu_url(congress, session),
               limiter: :senate_gov,
               decode: :raw
             ) do
        {:ok, raw |> SenateVote.menu() |> length()}
      end
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
