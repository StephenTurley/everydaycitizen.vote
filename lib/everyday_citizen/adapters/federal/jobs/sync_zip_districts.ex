defmodule EverydayCitizen.Adapters.Federal.Jobs.SyncZipDistricts do
  @moduledoc """
  Loads Census's district to ZIP area relationship file for the sitting congress
  (about 6 MB; `config :everyday_citizen, :federal, zip_files: %{congress => url}`)
  into the postal-code table, replacing it. Districts change only between
  congresses, so this runs by name (`zip_districts`), once per congress. Census
  publishes a congress's file months after it sits; until its URL is configured
  the job does nothing, and ZIP lookups ask for the street address instead.
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  alias EverydayCitizen.Adapters.Federal.{Congresses, HTTP, Job}
  alias EverydayCitizen.Adapters.Federal.Normalize.ZipDistricts
  alias EverydayCitizen.Ingest

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    congress = Congresses.current()
    url = Application.fetch_env!(:everyday_citizen, :federal)[:zip_files][congress]

    Job.run("sync_zip_districts", fn run_id, _cursor -> load(url, congress, run_id) end)
  end

  defp load(nil, _congress, _run_id), do: {:ok, %{skipped: :not_published}}

  defp load(url, congress, run_id) do
    with {:ok, %{raw: raw, source: source}} <- HTTP.get(url, decode: :raw, limiter: :census) do
      Ingest.write(ZipDistricts.parse(raw, source, congress), run_id)
    end
  end
end
