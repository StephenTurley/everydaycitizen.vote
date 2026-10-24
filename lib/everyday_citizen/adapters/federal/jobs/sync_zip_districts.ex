defmodule EverydayCitizen.Adapters.Federal.Jobs.SyncZipDistricts do
  @moduledoc """
  Loads Census's 119th-Congress district to ZIP area relationship file (about
  6 MB) into the postal-code table, replacing it. Districts change only between
  congresses, so this runs by name (`zip_districts`), once per congress.
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  alias EverydayCitizen.Adapters.Federal.{HTTP, Job}
  alias EverydayCitizen.Adapters.Federal.Normalize.ZipDistricts
  alias EverydayCitizen.Ingest

  @url "https://www2.census.gov/geo/docs/maps-data/data/rel2020/cd-sld/tab20_cd11920_zcta520_natl.txt"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Job.run("sync_zip_districts", fn run_id, _cursor ->
      with {:ok, %{raw: raw, source: source}} <- HTTP.get(@url, decode: :raw, limiter: :census) do
        Ingest.write(ZipDistricts.parse(raw, source), run_id)
      end
    end)
  end
end
