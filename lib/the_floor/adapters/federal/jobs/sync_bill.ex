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

  alias TheFloor.Adapters.Federal.{BillWriter, CongressGov}
  alias TheFloor.Adapters.Federal.Jobs.SyncBillText
  alias TheFloor.Adapters.Federal.Normalize.Bill, as: Normalize
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
         {:ok, summaries} <- fetch_all(base <> "/summaries", "summaries"),
         {:ok, id} <-
           BillWriter.write(
             %{
               detail: {detail, detail_src},
               subjects: subjects,
               actions: actions,
               cosponsors: cosponsors,
               text: {text, text_src},
               summaries: summaries
             },
             run_id
           ) do
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
