defmodule EverydayCitizen.Repo.Migrations.CreateBillContext do
  use Ecto.Migration

  def change do
    # committee steps on a bill (referred, markup, reported); body by its code
    create table(:bill_committee_activities) do
      add :bill_id, references(:bills, on_delete: :delete_all), null: false
      add :body_id, references(:bodies, on_delete: :nilify_all)
      add :body_ref, :string, null: false
      add :kind, :string, null: false
      add :date, :date
      add :source_id, references(:sources, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:bill_committee_activities, [:bill_id])

    # measures related to a bill; "procedural" ones govern how it is taken up
    create table(:bill_relations) do
      add :bill_id, references(:bills, on_delete: :delete_all), null: false
      add :related_ref, :string, null: false
      add :kind, :string, null: false
      add :source_id, references(:sources, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:bill_relations, [:bill_id, :kind])

    create table(:bill_amendments) do
      add :bill_id, references(:bills, on_delete: :delete_all), null: false
      add :external_id, :string, null: false
      add :identifier, :string, null: false
      add :description, :text
      add :latest_action, :text
      add :latest_action_date, :date
      add :url, :string
      add :source_id, references(:sources, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:bill_amendments, [:bill_id])
  end
end
