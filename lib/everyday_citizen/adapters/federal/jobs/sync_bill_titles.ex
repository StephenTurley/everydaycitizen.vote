defmodule EverydayCitizen.Adapters.Federal.Jobs.SyncBillTitles do
  @moduledoc """
  Fetches and stores the titles of one bill, for bills stored before titles were
  recorded. Runs on the `backfill` queue, one at a time, so it never crowds out
  the nightly jobs. A bill the source no longer has is done, not retried.
  """
  use Oban.Worker,
    queue: :backfill,
    max_attempts: 5,
    unique: [period: 3600, keys: [:congress, :type, :number]]

  alias EverydayCitizen.Adapters.Federal.CongressGov
  alias EverydayCitizen.Adapters.Federal.Normalize.BillContext
  alias EverydayCitizen.Ingest

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"congress" => c, "type" => t, "number" => n}}) do
    base = "/bill/#{c}/#{String.downcase(t)}/#{n}"

    case CongressGov.fetch_all(base <> "/titles", "titles") do
      {:ok, {[], _}} ->
        :ok

      {:ok, {items, source}} ->
        record = BillContext.titles(items, "#{c}-#{String.downcase(t)}-#{n}", source)

        with {:ok, _} <- Ingest.write(record, nil), do: :ok

      {:error, message} ->
        if message =~ "{:http_status, 404}", do: :ok, else: {:error, message}
    end
  end
end
