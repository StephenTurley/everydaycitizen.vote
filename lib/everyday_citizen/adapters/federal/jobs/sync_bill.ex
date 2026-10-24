defmodule EverydayCitizen.Adapters.Federal.Jobs.SyncBill do
  @moduledoc """
  Syncs one bill: detail + subjects, actions, sponsors/cosponsors, text-version
  metadata, committee steps, related measures and amendments (with the detail of
  agreed amendments that lack a description), then enqueues text fetches for
  versions that have no text yet.

  The action and sponsorship sets replace whatever is stored, so each is written
  only from a successful, non-empty fetch of its endpoint; a failed request fails
  the job (Oban retries) rather than deleting stored rows.
  """
  use Oban.Worker,
    queue: :ingest,
    priority: 5,
    max_attempts: 5,
    unique: [period: 3600, keys: [:congress, :type, :number]]

  alias EverydayCitizen.Adapters.Federal.{BillWriter, CongressGov}
  alias EverydayCitizen.Adapters.Federal.Jobs.SyncBillText
  alias EverydayCitizen.Adapters.Federal.Normalize.Bill, as: Normalize
  alias EverydayCitizen.Adapters.Federal.Normalize.BillContext
  alias EverydayCitizen.Legislation

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
         {:ok, committees} <- fetch_all(base <> "/committees", "committees"),
         {:ok, relations} <- fetch_all(base <> "/relatedbills", "relatedBills"),
         {:ok, amendments} <- fetch_all(base <> "/amendments", "amendments"),
         {:ok, details} <- amendment_details(elem(amendments, 0)),
         {:ok, id} <-
           BillWriter.write(
             %{
               detail: {detail, detail_src},
               subjects: subjects,
               actions: actions,
               cosponsors: cosponsors,
               text: {text, text_src},
               summaries: summaries,
               committees: committees,
               relations: relations,
               amendments: {amendments, details}
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

  # number => detail for agreed amendments the list gives no description for
  defp amendment_details(items) do
    items
    |> Enum.filter(&BillContext.needs_detail?/1)
    |> Enum.reduce_while({:ok, %{}}, fn item, {:ok, acc} ->
      path = "/amendment/#{item["congress"]}/#{String.downcase(item["type"])}/#{item["number"]}"

      case CongressGov.get(path) do
        {:ok, %{"amendment" => detail}, _} ->
          {:cont, {:ok, Map.put(acc, to_string(item["number"]), detail)}}

        {:ok, _other, _} ->
          {:cont, {:ok, acc}}

        error ->
          {:halt, error}
      end
    end)
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
