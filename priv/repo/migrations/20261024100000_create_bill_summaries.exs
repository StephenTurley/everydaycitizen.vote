defmodule TheFloor.Repo.Migrations.CreateBillSummaries do
  use Ecto.Migration

  def change do
    create table(:bill_summaries) do
      add :bill_id, references(:bills, on_delete: :delete_all), null: false
      add :version_code, :string
      add :action_date, :date
      add :action_description, :text
      add :author, :string, null: false
      add :html, :text, null: false
      add :updated_at_source, :utc_datetime_usec
      add :source_id, references(:sources, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:bill_summaries, [:bill_id, :version_code, :action_date],
             nulls_distinct: false
           )
  end
end
