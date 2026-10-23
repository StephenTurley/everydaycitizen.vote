defmodule TheFloor.Repo.Migrations.CreateCoverageChecks do
  use Ecto.Migration

  def change do
    create table(:coverage_checks) do
      add :ingest_run_id, references(:ingest_runs, on_delete: :nilify_all)
      add :name, :string, null: false
      add :expected, :integer
      add :actual, :integer
      add :tolerance, :float, null: false, default: 0.0
      add :passed, :boolean, null: false
      add :error, :text
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:coverage_checks, [:name, :id])
  end
end
