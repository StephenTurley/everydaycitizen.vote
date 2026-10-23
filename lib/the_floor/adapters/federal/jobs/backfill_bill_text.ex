defmodule TheFloor.Adapters.Federal.Jobs.BackfillBillText do
  @moduledoc """
  Loads bill version text from GovInfo's BILLS bulk zips (one per session and
  bill type) instead of one request per version. Only versions stored without
  text are written. A zip that cannot be fetched is skipped, and every version
  still missing text afterwards gets a `SyncBillText` job, so text the bulk
  files lack (or that failed to parse) still arrives.
  """
  use Oban.Worker, queue: :text, max_attempts: 3

  require Logger

  alias TheFloor.Adapters.Federal.{Bulk, HTTP, Job, Sessions, XmlText}
  alias TheFloor.Adapters.Federal.Jobs.SyncBillText
  alias TheFloor.Legislation

  @bulk "https://www.govinfo.gov/bulkdata/BILLS"
  @types ~w(hr s hjres sjres hconres sconres hres sres)

  # The bulk load runs for minutes; it must end before Lifeline (2 h) would
  # treat it as orphaned and start it again.
  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(90)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    congress = args["congress"] || Application.fetch_env!(:the_floor, :federal)[:congress]

    Job.run("backfill_bill_text", fn _run_id, _cursor ->
      missing = "federal" |> Legislation.version_keys_missing_text() |> MapSet.new()

      {missing, stored, failed_zips} =
        for session <- Sessions.numbers(congress, nil),
            type <- @types,
            reduce: {missing, 0, []} do
          acc -> backfill_zip(zip_url(congress, session, type), acc)
        end

      for {bill_id, code} <- missing do
        Oban.insert!(SyncBillText.new(%{"bill_external_id" => bill_id, "code" => code}))
      end

      {:ok, %{stored: stored, fallback: MapSet.size(missing), failed_zips: failed_zips}}
    end)
  end

  defp zip_url(congress, session, type),
    do: "#{@bulk}/#{congress}/#{session}/#{type}/BILLS-#{congress}-#{session}-#{type}.zip"

  defp backfill_zip(url, {missing, stored, failed}) do
    case Bulk.with_zip(
           url,
           &Bulk.reduce_entries(&1, {missing, stored}, fn e, a -> entry(e, a) end)
         ) do
      {:ok, {missing, stored}} ->
        {missing, stored, failed}

      {:error, reason} ->
        Logger.warning("backfill_bill_text: skipped #{url}: #{inspect(reason)}")
        {missing, stored, [Path.basename(url) | failed]}
    end
  end

  # A version whose entry is unreadable, unparseable or fails to store (raised or
  # returned) stays in `missing` and falls back to `SyncBillText`.
  defp entry({_name, {:error, _}, nil}, acc), do: acc

  defp entry({name, xml, source}, {missing, stored} = acc) do
    with {:ok, key} <- version_key(name),
         true <- MapSet.member?(missing, key),
         false <- HTTP.html?(xml),
         {:ok, text} <- XmlText.plain_text(xml),
         :ok <- store(xml, text, source, key) do
      {MapSet.delete(missing, key), stored + 1}
    else
      _ -> acc
    end
  end

  defp store(xml, text, source, {bill_id, code} = key) do
    SyncBillText.store(xml, text, source, bill_id, code)
  rescue
    e ->
      Logger.warning("backfill_bill_text: #{inspect(key)} not stored: #{Exception.message(e)}")
      :error
  end

  # `BILLS-119hr152ih.xml` -> {"119-hr-152", "ih"}
  defp version_key(name) do
    case Regex.run(~r/^BILLS-(\d+)([a-z]+?)(\d+)([a-z]+)\.xml$/, name) do
      [_, congress, type, number, code] -> {:ok, {"#{congress}-#{type}-#{number}", code}}
      _ -> :error
    end
  end
end
