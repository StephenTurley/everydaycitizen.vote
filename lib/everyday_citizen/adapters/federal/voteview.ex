defmodule EverydayCitizen.Adapters.Federal.Voteview do
  @moduledoc """
  Senate roll-call votes from Voteview (UCLA), used because senate.gov answers
  automated clients with 403. Only Voteview's documented bulk files are fetched
  (https://voteview.com/data): three small CSVs per congress, one at a time
  through the `:voteview` rate limiter. Voteview publishes no terms or rate
  limits; it asks to be cited as:

  Lewis, Jeffrey B., Keith Poole, Howard Rosenthal, Adam Boche, Aaron Rudkin,
  and Luke Sonnet. Voteview: Congressional Roll-Call Votes Database.
  https://voteview.com/
  """
  alias EverydayCitizen.Adapters.Federal.HTTP
  alias EverydayCitizen.Ingest.Records.SourceRef

  @base "https://voteview.com/static/data/out"

  @doc "URL of one Senate bulk file (`rollcalls`, `votes` or `members`)."
  @spec url(String.t(), integer()) :: String.t()
  def url(kind, congress), do: "#{@base}/#{kind}/S#{congress}_#{kind}.csv"

  @doc "The roll-call list only (for coverage counts)."
  @spec rollcalls(integer()) :: {:ok, binary()} | {:error, term()}
  def rollcalls(congress) do
    with {:ok, %{raw: raw}} <- get("rollcalls", congress), do: {:ok, raw}
  end

  @doc """
  All three files, plus the source of the votes file: positions, the bulk of
  each vote record, come from it.
  """
  @spec files(integer()) ::
          {:ok, %{rollcalls: binary(), votes: binary(), members: binary()}, SourceRef.t()}
          | {:error, term()}
  def files(congress) do
    with {:ok, %{raw: rollcalls}} <- get("rollcalls", congress),
         {:ok, %{raw: votes, source: source}} <- get("votes", congress),
         {:ok, %{raw: members}} <- get("members", congress) do
      {:ok, %{rollcalls: rollcalls, votes: votes, members: members}, source}
    end
  end

  defp get(kind, congress), do: HTTP.get(url(kind, congress), limiter: :voteview, decode: :raw)
end
