defmodule TheFloor.Adapters.Federal.Jobs.BulkBillsChunk do
  @moduledoc """
  Writes one slice (`offset`, `limit`) of a BILLSTATUS bulk zip, for the first
  `SyncBills` run (`Federal.BulkBatch`). A bill already stored with the same
  source update time is skipped, so a retried or repeated chunk only does the work
  left. An entry that cannot be read or written falls back to a `SyncBill` job. A
  missing zip (404, or GovInfo's HTML error page) writes nothing; any other
  download failure fails the chunk for retry.
  """
  use Oban.Worker,
    queue: :bulk,
    max_attempts: 3,
    unique: [period: :infinity, keys: [:batch, :type, :offset], states: :incomplete]

  require Logger

  alias TheFloor.Adapters.Federal.{BillWriter, Bulk, Job}
  alias TheFloor.Adapters.Federal.Jobs.SyncBill
  alias TheFloor.Adapters.Federal.Normalize.{Bill, BillStatus}
  alias TheFloor.Legislation

  @bulk "https://www.govinfo.gov/bulkdata/BILLSTATUS"

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  @doc "URL of the BILLSTATUS zip for a congress and bill type."
  @spec zip_url(integer(), String.t()) :: String.t()
  def zip_url(congress, type),
    do: "#{@bulk}/#{congress}/#{type}/BILLSTATUS-#{congress}-#{type}.zip"

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"congress" => c, "type" => t, "offset" => o, "limit" => l} = args
      }) do
    Job.run("bulk_bills_chunk", fn run_id, _cursor ->
      zero = %{"batch" => args["batch"], "written" => 0, "unchanged" => 0, "fallback" => 0}

      case Bulk.with_zip(zip_url(c, t), &write_slice(&1, o, l, zero, c, run_id)) do
        {:ok, stats} ->
          {:ok, stats}

        {:error, reason} when reason in [:not_a_zip, {:http_status, 404}] ->
          Logger.warning("bulk_bills_chunk: no zip for #{c} #{t}: #{inspect(reason)}")
          {:ok, zero}

        {:error, _} = error ->
          error
      end
    end)
  end

  defp write_slice(zip, offset, limit, zero, congress, run_id) do
    Bulk.reduce_entries(zip, zero, &entry(&1, &2, congress, run_id), range: {offset, limit})
  end

  # Any failure on one entry, raised or returned, falls back to the API for that
  # bill, so a single bad file never blocks the backfill.
  defp entry({name, xml, source}, stats, congress, run_id) do
    case write_entry(xml, source, run_id) do
      :written ->
        Map.update!(stats, "written", &(&1 + 1))

      :unchanged ->
        Map.update!(stats, "unchanged", &(&1 + 1))

      error ->
        Logger.warning(
          "bulk_bills_chunk: entry #{name} failed (#{inspect(error)}); using the API"
        )

        fallback(name, congress, run_id, stats)
    end
  end

  defp write_entry({:error, _} = error, _source, _run_id), do: error

  defp write_entry(xml, source, run_id) do
    with {:ok, parts} <- BillStatus.parse(xml) do
      if unchanged?(parts, source), do: :unchanged, else: write(parts, source, run_id)
    end
  rescue
    e -> {:exception, Exception.message(e)}
  end

  defp write(parts, source, run_id) do
    with {:ok, _id} <- BillWriter.write(bulk_parts(parts, source), run_id), do: :written
  end

  defp unchanged?(parts, source) do
    record = Bill.bill(parts.detail, parts.subjects, source)

    case Legislation.get_bill(record.jurisdiction, record.external_id) do
      %{updated_at_source: %DateTime{} = stored} when not is_nil(record.updated_at_source) ->
        DateTime.compare(stored, record.updated_at_source) == :eq

      _ ->
        false
    end
  end

  defp bulk_parts(parts, source) do
    %{
      detail: {parts.detail, source},
      subjects: parts.subjects,
      actions: {parts.actions, source},
      cosponsors: {parts.cosponsors, source},
      text: {parts.text, source}
    }
  end

  # `BILLSTATUS-119hr152.xml` names the bill when its contents cannot be read.
  defp fallback(name, congress, run_id, stats) do
    case Regex.run(~r/^BILLSTATUS-\d+([a-z]+)(\d+)\.xml$/, name) do
      [_, type, number] ->
        %{"congress" => congress, "type" => type, "number" => number, "run_id" => run_id}
        |> SyncBill.new()
        |> Oban.insert!()

        Map.update!(stats, "fallback", &(&1 + 1))

      _ ->
        stats
    end
  end
end
