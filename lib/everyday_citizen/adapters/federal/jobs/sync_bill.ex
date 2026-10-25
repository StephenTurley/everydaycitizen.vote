defmodule EverydayCitizen.Adapters.Federal.Jobs.SyncBill do
  @moduledoc """
  Syncs one bill: detail + subjects, actions, sponsors/cosponsors, text-version
  metadata, committee steps, related measures, titles and amendments (with the detail of
  agreed amendments that lack a description), then enqueues text fetches for
  versions that have no text yet.

  The action and sponsorship sets replace whatever is stored, so each is written
  only from a successful, non-empty fetch of its endpoint; a failed request fails
  the job (Oban retries) rather than deleting stored rows.
  """
  require Logger

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
         {:ok, actions} <- CongressGov.fetch_all(base <> "/actions", "actions"),
         {:ok, cosponsors} <- CongressGov.fetch_all(base <> "/cosponsors", "cosponsors"),
         {:ok, text, text_src} <- CongressGov.get(base <> "/text", limit: 250),
         {:ok, summaries} <- CongressGov.fetch_all(base <> "/summaries", "summaries"),
         {:ok, committees} <- CongressGov.fetch_all(base <> "/committees", "committees"),
         {:ok, relations} <- CongressGov.fetch_all(base <> "/relatedbills", "relatedBills"),
         {:ok, titles} <- CongressGov.fetch_all(base <> "/titles", "titles"),
         {:ok, amendments} <- CongressGov.fetch_all(base <> "/amendments", "amendments"),
         details = amendment_details(elem(amendments, 0), "#{c}"),
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
               titles: titles,
               amendments: {amendments, details}
             },
             run_id
           ) do
      enqueue_text(id, text, text_src)
    end
  end

  # type+number => detail, for agreed amendments the list gives no description
  # for and that aren't stored with one already; a failed detail is skipped
  # (the amendment keeps its latest action) rather than failing the bill
  defp amendment_details(items, congress) do
    described = Legislation.described_amendment_ids()

    for item <- items,
        BillContext.needs_detail?(item),
        not MapSet.member?(
          described,
          "#{congress}-#{String.downcase(item["type"])}-#{item["number"]}"
        ),
        detail = fetch_detail(item),
        detail != nil,
        into: %{},
        do: {BillContext.detail_key(item), detail}
  end

  defp fetch_detail(item) do
    path = "/amendment/#{item["congress"]}/#{String.downcase(item["type"])}/#{item["number"]}"

    case CongressGov.get(path) do
      {:ok, %{"amendment" => detail}, _} ->
        detail

      other ->
        Logger.warning(
          "amendment detail #{BillContext.detail_key(item)} skipped: #{inspect(other)}"
        )

        nil
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
