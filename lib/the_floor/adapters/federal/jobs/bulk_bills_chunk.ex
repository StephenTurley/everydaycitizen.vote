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
    unique: [period: :infinity, keys: [:batch, :type, :offset, :only], states: :incomplete]

  require Logger

  alias TheFloor.Adapters.Federal.{BillWriter, Bulk, BulkBatch, Job}
  alias TheFloor.Adapters.Federal.Jobs.SyncBill
  alias TheFloor.Adapters.Federal.Normalize.{Bill, BillStatus}
  alias TheFloor.{Ingest, Legislation}

  @bulk "https://www.govinfo.gov/bulkdata/BILLSTATUS"

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  @doc "URL of the BILLSTATUS zip for a congress and bill type."
  @spec zip_url(integer(), String.t()) :: String.t()
  def zip_url(congress, type),
    do: "#{@bulk}/#{congress}/#{type}/BILLSTATUS-#{congress}-#{type}.zip"

  @types ~w(hr s hjres sjres hconres sconres hres sres)

  @doc """
  Chunk args covering every bill type's zip for the congress: one chunk per
  `BulkBatch.chunk_size/0` entries. A type with no zip (404, or GovInfo's HTML
  error page) has no chunks; any other download failure is an error.
  """
  @spec chunks(integer()) :: {:ok, [map()]} | {:error, term()}
  def chunks(congress) do
    Enum.reduce_while(@types, {:ok, []}, fn type, {:ok, chunks} ->
      case type_chunks(congress, type) do
        {:ok, more} -> {:cont, {:ok, chunks ++ more}}
        error -> {:halt, error}
      end
    end)
  end

  defp type_chunks(congress, type) do
    case Bulk.with_zip(zip_url(congress, type), &Bulk.count_entries/1) do
      {:ok, count} ->
        extra = %{"congress" => congress, "type" => type}
        {:ok, Enum.map(BulkBatch.slices(count), &Map.merge(&1, extra))}

      {:error, reason} when reason in [:not_a_zip, {:http_status, 404}] ->
        Logger.warning(
          "bulk_bills_chunk: no bulk zip for #{congress} #{type}: #{inspect(reason)}"
        )

        {:ok, []}

      {:error, reason} ->
        {:error, {:bulk_zip, type, reason}}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"congress" => c, "type" => t, "offset" => o, "limit" => l} = args
      }) do
    Job.run("bulk_bills_chunk", fn run_id, _cursor ->
      zero = %{"batch" => args["batch"], "written" => 0, "unchanged" => 0, "fallback" => 0}

      only = args["only"]
      zero = if only, do: Map.put(zero, "skipped", 0), else: zero

      case Bulk.with_zip(zip_url(c, t), &write_slice(&1, {o, l}, zero, {c, run_id, only})) do
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

  defp write_slice(zip, range, zero, ctx),
    do: Bulk.reduce_entries(zip, zero, &entry(&1, &2, ctx), range: range)

  # `only: "summaries"` (`BackfillBillSummaries`): write just each stored bill's
  # summary set; anything else about the entry is left alone and never falls back.
  defp entry({_name, xml, source}, stats, {_c, run_id, "summaries"}) do
    case write_summaries(xml, source, run_id) do
      :written -> Map.update!(stats, "written", &(&1 + 1))
      _ -> Map.update!(stats, "skipped", &(&1 + 1))
    end
  end

  # Any failure on one entry, raised or returned, falls back to the API for that
  # bill, so a single bad file never blocks the backfill.
  defp entry({name, xml, source}, stats, {congress, run_id, nil}) do
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

  defp write_summaries({:error, _} = error, _source, _run_id), do: error

  defp write_summaries(xml, source, run_id) do
    with {:ok, %{summaries: [_ | _] = summaries} = parts} <- BillStatus.parse(xml),
         id = Bill.external_id(parts.detail),
         {:ok, _} <- Ingest.write(Bill.summaries(summaries, id, source), run_id) do
      :written
    end
  rescue
    e -> {:exception, Exception.message(e)}
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
      text: {parts.text, source},
      summaries: {parts.summaries, source}
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
