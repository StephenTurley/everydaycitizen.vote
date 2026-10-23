defmodule TheFloor.Adapters.Federal.Jobs.SyncCommitteeMeeting do
  @moduledoc """
  Fetches and stores one committee meeting (`congress`, `chamber`, `event_id`).

  A meeting whose committee is not stored is written without a body: an unknown
  committee must not fail the event.
  """
  use Oban.Worker, queue: :ingest, max_attempts: 5

  alias TheFloor.Adapters.Federal.CongressGov
  alias TheFloor.Adapters.Federal.Normalize.CommitteeMeeting
  alias TheFloor.Ingest
  alias TheFloor.Legislature

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"congress" => congress, "chamber" => chamber, "event_id" => id} = args
      }) do
    with {:ok, detail, source} <-
           CongressGov.get("/committee-meeting/#{congress}/#{chamber}/#{id}"),
         event = known_body(CommitteeMeeting.event(detail, source)),
         {:ok, _event} <- Ingest.write(event, args["run_id"]) do
      :ok
    end
  end

  defp known_body(%{body_external_id: nil} = event), do: event

  defp known_body(event) do
    if Legislature.get_body(event.jurisdiction, event.body_external_id),
      do: event,
      else: %{event | body_external_id: nil}
  end
end
