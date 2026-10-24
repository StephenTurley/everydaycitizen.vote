defmodule EverydayCitizen.Adapters.Federal.Jobs.BulkBillTextChunk do
  @moduledoc """
  Stores version text for one slice (`offset`, `limit`) of a BILLS bulk zip, for
  `BackfillBillText` (`Federal.BulkBatch`). Only versions stored without text are
  written, so a retried or repeated chunk only does the work left. Entries for
  unknown versions, HTML error pages and unparseable XML are skipped; the
  coordinator's fallback fetches whatever is still missing. A missing zip writes
  nothing; any other download failure fails the chunk for retry.
  """
  use Oban.Worker,
    queue: :bulk,
    max_attempts: 3,
    unique: [period: :infinity, keys: [:batch, :session, :type, :offset], states: :incomplete]

  require Logger

  alias EverydayCitizen.Adapters.Federal.{Bulk, HTTP, Job, XmlText}
  alias EverydayCitizen.Adapters.Federal.Jobs.SyncBillText
  alias EverydayCitizen.Legislation

  @bulk "https://www.govinfo.gov/bulkdata/BILLS"

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  @doc "URL of the BILLS zip for a congress, session and bill type."
  @spec zip_url(integer(), integer(), String.t()) :: String.t()
  def zip_url(congress, session, type),
    do: "#{@bulk}/#{congress}/#{session}/#{type}/BILLS-#{congress}-#{session}-#{type}.zip"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"congress" => c, "session" => s, "type" => t} = args}) do
    Job.run("bulk_bill_text_chunk", fn _run_id, _cursor ->
      zero = %{"batch" => args["batch"], "stored" => 0}
      range = {args["offset"], args["limit"]}

      case Bulk.with_zip(zip_url(c, s, t), &store_slice(&1, zero, range)) do
        {:ok, stats} ->
          {:ok, stats}

        {:error, reason} when reason in [:not_a_zip, {:http_status, 404}] ->
          Logger.warning("bulk_bill_text_chunk: no zip for #{c}-#{s} #{t}: #{inspect(reason)}")
          {:ok, zero}

        {:error, _} = error ->
          error
      end
    end)
  end

  defp store_slice(zip, zero, range),
    do: Bulk.reduce_entries(zip, zero, &entry/2, range: range)

  # Unreadable entries arrive as `{:error, _}`; the fallback covers their versions.
  defp entry({_name, {:error, _}, nil}, stats), do: stats

  defp entry({name, xml, source}, stats) do
    with {:ok, {bill_id, code} = key} <- version_key(name),
         true <- missing_text?(bill_id, code),
         false <- HTTP.html?(xml),
         {:ok, text} <- XmlText.plain_text(xml),
         :ok <- store(xml, text, source, key) do
      Map.update!(stats, "stored", &(&1 + 1))
    else
      _ -> stats
    end
  end

  defp missing_text?(bill_id, code) do
    with %{} = bill <- Legislation.get_bill("federal", bill_id),
         %{text_source_id: nil} <- Legislation.get_version(bill, code) do
      true
    else
      _ -> false
    end
  end

  defp store(xml, text, source, {bill_id, code} = key) do
    SyncBillText.store(xml, text, source, bill_id, code)
  rescue
    e ->
      Logger.warning("bulk_bill_text_chunk: #{inspect(key)} not stored: #{Exception.message(e)}")
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
