defmodule TheFloor.Adapters.Federal.Jobs.SyncCommitteeMeeting do
  @moduledoc """
  Fetches and stores one committee meeting (`congress`, `chamber`, `event_id`).

  A meeting whose committee is not stored is written without a body: an unknown
  committee must not fail the event.
  """
  use Oban.Worker, queue: :ingest, priority: 5, max_attempts: 5

  require Logger

  alias TheFloor.Adapters.Federal.CongressGov
  alias TheFloor.Adapters.Federal.Normalize.CommitteeMeeting
  alias TheFloor.Ingest
  alias TheFloor.Legislature

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"congress" => congress, "chamber" => chamber, "event_id" => id} = args
      }) do
    with {:ok, detail, source} <-
           CongressGov.get("/committee-meeting/#{congress}/#{chamber}/#{id}") do
      write(CommitteeMeeting.event(detail, source), id, args["run_id"])
    end
  end

  defp write(%{start_at: nil}, id, _run_id) do
    Logger.warning("Skipping committee meeting #{id}: missing or invalid date")
    :ok
  end

  defp write(event, _id, run_id) do
    with {:ok, _event} <- Ingest.write(known_body(event), run_id), do: :ok
  end

  defp known_body(%{body_external_id: nil} = event), do: event

  defp known_body(event) do
    if Legislature.get_body(event.jurisdiction, event.body_external_id),
      do: event,
      else: %{event | body_external_id: nil}
  end
end
