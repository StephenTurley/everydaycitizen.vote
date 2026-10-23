defmodule TheFloor.Ingest.Writer.Calendar do
  @moduledoc """
  Persists calendar events. Natural key `(jurisdiction, external_id)`.

  The event's bill links are replaced as a set: found bills are upserted into
  `event_bills` and the event's other links deleted. Bill references not found
  (plus the adapter's `raw_bill_labels`) are kept on the event as
  `unresolved_bill_labels`. An unknown body is `{:error, {:unknown_body, id}}`.
  Returns `{:ok, event}`.
  """
  import Ecto.Query

  alias TheFloor.Calendar.{Event, EventBill}
  alias TheFloor.Ingest.Records
  alias TheFloor.Ingest.Writer.Support
  alias TheFloor.Legislation
  alias TheFloor.Repo

  import Support, only: [body: 2, jurisdiction: 1, upsert: 3]

  @spec write(Records.Event.t(), integer() | nil) :: {:ok, Event.t()} | {:error, term()}
  def write(%Records.Event{} = r, run_id) do
    Support.transact(r, run_id, &do_write(r, &1))
  end

  defp do_write(r, source_id) do
    with {:ok, j} <- jurisdiction(r.jurisdiction),
         {:ok, body} <- body(j.id, r.body_external_id) do
      {found, missing} = resolve_bills(r.jurisdiction, Enum.uniq(r.bill_external_ids))

      with {:ok, event} <-
             upsert(
               Event,
               %{
                 jurisdiction_id: j.id,
                 body_id: body && body.id,
                 external_id: r.external_id,
                 classification: r.classification,
                 raw_classification: r.raw_classification,
                 status: r.status,
                 title: r.title,
                 start_at: r.start_at,
                 all_day: r.all_day,
                 location: r.location,
                 unresolved_bill_labels: r.raw_bill_labels ++ missing,
                 source_id: source_id
               },
               [:jurisdiction_id, :external_id]
             ),
           {:ok, ids} <- link_bills(event, found, source_id) do
        Repo.delete_all(from l in EventBill, where: l.event_id == ^event.id and l.id not in ^ids)
        {:ok, event}
      end
    end
  end

  defp resolve_bills(jurisdiction, external_ids) do
    {found, missing} =
      Enum.reduce(external_ids, {[], []}, fn id, {found, missing} ->
        case Legislation.get_bill(jurisdiction, id) do
          nil -> {found, [id | missing]}
          bill -> {[bill | found], missing}
        end
      end)

    {Enum.reverse(found), Enum.reverse(missing)}
  end

  defp link_bills(event, bills, source_id) do
    Enum.reduce_while(bills, {:ok, []}, fn bill, {:ok, ids} ->
      case upsert(
             EventBill,
             %{event_id: event.id, bill_id: bill.id, source_id: source_id},
             [:event_id, :bill_id]
           ) do
        {:ok, link} -> {:cont, {:ok, [link.id | ids]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end
end
