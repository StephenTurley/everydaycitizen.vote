defmodule EverydayCitizen.Repo.Migrations.CreateProvenance do
  use Ecto.Migration

  def change do
    create table(:ingest_runs) do
      add :adapter, :string, null: false
      add :job, :string, null: false
      add :status, :string, null: false, default: "running"
      add :started_at, :utc_datetime_usec, null: false
      add :finished_at, :utc_datetime_usec
      add :stats, :map, null: false, default: %{}
      add :error, :text
    end

    create index(:ingest_runs, [:adapter, :job, :status, :started_at])

    create table(:sources) do
      add :url, :text, null: false
      add :fetched_at, :utc_datetime_usec, null: false
      add :last_seen_at, :utc_datetime_usec, null: false
      add :content_hash, :string, null: false
      add :ingest_run_id, references(:ingest_runs, on_delete: :nilify_all)
    end

    create unique_index(:sources, [:url, :content_hash])
    create index(:sources, [:ingest_run_id])
  end
end
