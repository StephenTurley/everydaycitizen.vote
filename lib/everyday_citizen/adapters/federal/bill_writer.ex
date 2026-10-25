defmodule EverydayCitizen.Adapters.Federal.BillWriter do
  @moduledoc """
  Writes one bill's parts (detail, subjects, actions, cosponsors, text versions)
  in API shape, whichever source they came from: Congress.gov responses
  (`SyncBill`) or a BILLSTATUS bulk file (`SyncBills` first run). Each part
  carries the `SourceRef` of the document it came from.

  The action and sponsorship sets replace whatever is stored, so an empty action
  list writes nothing rather than deleting stored rows.
  """
  require Logger

  alias EverydayCitizen.Adapters.Federal.Normalize.Bill, as: Normalize
  alias EverydayCitizen.Adapters.Federal.Normalize.BillContext
  alias EverydayCitizen.Ingest

  @type part(t) :: {t, EverydayCitizen.Ingest.Records.SourceRef.t() | nil}
  @type parts :: %{
          required(:detail) => part(map()),
          required(:subjects) => map(),
          required(:actions) => part([map()]),
          required(:cosponsors) => part([map()]),
          required(:text) => part(map()),
          optional(:summaries) => part([map()]),
          optional(:committees) => part([map()]),
          optional(:relations) => part([map()]),
          optional(:titles) => part([map()]),
          optional(:amendments) => {part([map()]), %{String.t() => map()}}
        }

  @doc "Writes the bill and its parts; returns its external id."
  @spec write(parts(), integer() | nil) :: {:ok, String.t()} | {:error, term()}
  def write(%{detail: {detail, detail_src}, subjects: subjects} = parts, run_id) do
    id = Normalize.external_id(detail)

    # One transaction, so a bill is never stored without its actions and sponsors
    # (the bulk load skips bills already stored).
    Ingest.atomically(fn ->
      with {:ok, _} <- Ingest.write(Normalize.bill(detail, subjects, detail_src), run_id),
           :ok <- write_actions(parts.actions, id, run_id),
           :ok <- write_sponsorships(detail, detail_src, parts.cosponsors, id, run_id),
           :ok <- write_versions(parts.text, id, run_id),
           :ok <- write_summaries(Map.get(parts, :summaries, {[], nil}), id, run_id),
           :ok <- write_context(parts, id, run_id) do
        {:ok, id}
      end
    end)
  end

  defp write_actions({[], _}, _id, _run_id), do: :ok

  defp write_actions({items, source}, id, run_id),
    do: write_record(Normalize.actions(items, id, source), run_id)

  defp write_sponsorships(detail, detail_src, {items, source}, id, run_id) do
    # An empty cosponsor list has no response source of its own; the sponsor alone
    # then comes from the detail response.
    source = source || detail_src
    record = Normalize.sponsorships(detail, items, id, source)

    case Ingest.write(record, run_id) do
      {:ok, %{skipped_people: []}} ->
        :ok

      {:ok, %{skipped_people: skipped}} ->
        Logger.warning("bill #{id}: skipped unknown people #{inspect(skipped)}")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Committee steps, related measures, titles and amendments; like actions, an empty
  # list (which has no response source) writes nothing.
  defp write_context(parts, id, run_id) do
    {amendments, details} = Map.get(parts, :amendments, {{[], nil}, %{}})

    [
      {Map.get(parts, :committees, {[], nil}), &BillContext.committees(&1, id, &2)},
      {Map.get(parts, :relations, {[], nil}), &BillContext.relations(&1, id, &2)},
      {Map.get(parts, :titles, {[], nil}), &BillContext.titles(&1, id, &2)},
      {amendments, &BillContext.amendments(&1, details, id, &2)}
    ]
    |> Enum.reduce_while(:ok, fn
      {{[], _}, _build}, :ok ->
        {:cont, :ok}

      {{items, source}, build}, :ok ->
        case write_record(build.(items, source), run_id) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
    end)
  end

  # Like actions: an empty list writes nothing rather than deleting stored rows.
  defp write_summaries({[], _}, _id, _run_id), do: :ok

  defp write_summaries({items, source}, id, run_id),
    do: write_record(Normalize.summaries(items, id, source), run_id)

  defp write_versions({text, source}, id, run_id) do
    text["textVersions"]
    |> Kernel.||([])
    |> Normalize.versions(id, source)
    |> Enum.reduce_while(:ok, fn version, :ok ->
      case Ingest.write(version, run_id) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp write_record(record, run_id) do
    case Ingest.write(record, run_id) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
