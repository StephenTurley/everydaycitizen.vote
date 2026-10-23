defmodule TheFloor.Adapters.Federal.Jobs.SyncBill do
  @moduledoc """
  Syncs one bill: detail + subjects, actions, sponsors/cosponsors and text-version
  metadata, then enqueues text fetches for versions that have no text yet.

  The action and sponsorship sets replace whatever is stored, so each is written
  only from a successful, non-empty fetch of its endpoint; a failed request fails
  the job (Oban retries) rather than deleting stored rows.
  """
  use Oban.Worker,
    queue: :ingest,
    priority: 5,
    max_attempts: 5,
    unique: [period: 3600, keys: [:congress, :type, :number]]

  require Logger

  alias TheFloor.Adapters.Federal.CongressGov
  alias TheFloor.Adapters.Federal.Jobs.SyncBillText
  alias TheFloor.Adapters.Federal.Normalize.Bill, as: Normalize
  alias TheFloor.Ingest
  alias TheFloor.Legislation

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"congress" => c, "type" => t, "number" => n} = args}) do
    run_id = args["run_id"]
    base = "/bill/#{c}/#{String.downcase(t)}/#{n}"

    with {:ok, detail, detail_src} <- CongressGov.get(base),
         {:ok, subjects, _src} <- CongressGov.get(base <> "/subjects", limit: 250),
         {:ok, actions} <- fetch_all(base <> "/actions", "actions"),
         {:ok, cosponsors} <- fetch_all(base <> "/cosponsors", "cosponsors"),
         {:ok, text, text_src} <- CongressGov.get(base <> "/text", limit: 250),
         id = Normalize.external_id(detail),
         {:ok, _} <- Ingest.write(Normalize.bill(detail, subjects, detail_src), run_id),
         :ok <- write_actions(actions, id, run_id),
         :ok <- write_sponsorships(detail, detail_src, cosponsors, id, run_id),
         :ok <- write_versions(text, text_src, id, run_id) do
      enqueue_text(id, text, text_src)
    end
  end

  # Items from every page plus the first page's source; `nil` source means no items.
  defp fetch_all(path, key) do
    items = path |> CongressGov.paginate(key) |> Enum.to_list()
    source = items |> List.first() |> then(&(&1 && elem(&1, 1)))
    {:ok, {Enum.map(items, &elem(&1, 0)), source}}
  rescue
    e in RuntimeError -> {:error, Exception.message(e)}
  end

  defp write_actions({[], _}, _id, _run_id), do: :ok

  defp write_actions({items, source}, id, run_id),
    do: write(Normalize.actions(items, id, source), run_id)

  defp write_sponsorships(detail, detail_src, {items, source}, id, run_id) do
    # An empty cosponsor list has no response source of its own; the sponsor alone
    # then comes from the detail response.
    source = source || detail_src
    record = Normalize.sponsorships(detail, items, id, source)

    case Ingest.write(record, run_id) do
      {:ok, %{skipped_people: []}} ->
        :ok

      {:ok, %{skipped_people: skipped}} ->
        Logger.warning("sync_bill #{id}: skipped unknown people #{inspect(skipped)}")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write_versions(text, source, id, run_id) do
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

  defp write(record, run_id) do
    case Ingest.write(record, run_id) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp enqueue_text(id, text, source) do
    bill = Legislation.get_bill("federal", id)

    for version <- Normalize.versions(text["textVersions"] || [], id, source),
        row = Legislation.get_version(bill, version.code),
        is_nil(row.text_source_id) do
      Oban.insert!(SyncBillText.new(%{"bill_external_id" => id, "code" => version.code}))
    end

    :ok
  end
end
