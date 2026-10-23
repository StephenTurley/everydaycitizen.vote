defmodule TheFloor.Provenance do
  @moduledoc """
  Provenance bookkeeping: deduplicated `sources` and `ingest_runs`.
  """
  import Ecto.Query

  alias TheFloor.Ingest.Records.SourceRef
  alias TheFloor.Provenance.{IngestRun, Source}
  alias TheFloor.Repo

  @doc """
  Inserts the source, or on `(url, content_hash)` conflict advances `last_seen_at`
  (keeping the original `fetched_at`).
  """
  @spec upsert_source(SourceRef.t(), integer() | nil) :: {:ok, Source.t()}
  def upsert_source(%SourceRef{} = ref, run_id) do
    now = DateTime.utc_now()

    source =
      Repo.insert!(
        %Source{
          url: ref.url,
          fetched_at: ref.fetched_at,
          last_seen_at: now,
          content_hash: ref.content_hash,
          ingest_run_id: run_id
        },
        on_conflict: [set: [last_seen_at: now]],
        conflict_target: [:url, :content_hash],
        returning: true
      )

    {:ok, source}
  end

  @spec start_run(String.t(), String.t()) :: {:ok, IngestRun.t()}
  def start_run(adapter, job) do
    {:ok,
     Repo.insert!(%IngestRun{
       adapter: adapter,
       job: job,
       status: :running,
       started_at: DateTime.utc_now()
     })}
  end

  @spec finish_run(IngestRun.t(), :succeeded | :failed, map(), String.t() | nil) ::
          {:ok, IngestRun.t()}
  def finish_run(%IngestRun{} = run, status, stats, error) when status in [:succeeded, :failed] do
    {:ok,
     run
     |> Ecto.Changeset.change(
       status: status,
       finished_at: DateTime.utc_now(),
       stats: stats,
       error: error
     )
     |> Repo.update!()}
  end

  @doc "Most recent succeeded run for the job; its `started_at` is the incremental cursor."
  @spec last_succeeded_run(String.t(), String.t()) :: IngestRun.t() | nil
  def last_succeeded_run(adapter, job) do
    IngestRun
    |> where([r], r.adapter == ^adapter and r.job == ^job and r.status == :succeeded)
    |> order_by([r], desc: r.started_at, desc: r.id)
    |> limit(1)
    |> Repo.one()
  end
end
