defmodule TheFloor.Adapters.Federal.Jobs.SyncSenateVote do
  @moduledoc """
  Fetches and stores one Senate roll-call vote (`congress`, `session`, `roll`).
  """
  use Oban.Worker, queue: :ingest, priority: 5, max_attempts: 5

  alias TheFloor.Adapters.Federal.HTTP
  alias TheFloor.Adapters.Federal.Normalize.SenateVote
  alias TheFloor.Ingest

  @base "https://www.senate.gov/legislative/LIS/roll_call_votes"

  @doc "Source URL of one roll-call vote document."
  @spec url(integer(), integer(), integer()) :: String.t()
  def url(congress, session, roll) do
    padded = roll |> Integer.to_string() |> String.pad_leading(5, "0")
    "#{@base}/vote#{congress}#{session}/vote_#{congress}_#{session}_#{padded}.xml"
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"congress" => c, "session" => s, "roll" => roll} = args}) do
    with {:ok, %{raw: raw, source: source}} <-
           HTTP.get(url(c, s, roll), limiter: :senate_gov, decode: :raw),
         {:ok, _vote} <- Ingest.write(SenateVote.vote(raw, source), args["run_id"]) do
      :ok
    end
  end
end
