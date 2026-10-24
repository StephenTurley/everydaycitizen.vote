defmodule EverydayCitizen.Repo.Migrations.CreateLegislation do
  use Ecto.Migration

  def change do
    create table(:bills) do
      add :jurisdiction_id, references(:jurisdictions, on_delete: :delete_all), null: false
      add :session_id, references(:legislative_sessions, on_delete: :delete_all), null: false
      add :from_body_id, references(:bodies, on_delete: :nilify_all)
      add :external_id, :string, null: false
      add :identifier, :string, null: false
      add :classification, :string, null: false
      add :title, :text, null: false
      add :subjects, {:array, :string}, null: false, default: []
      add :introduced_on, :date
      add :updated_at_source, :utc_datetime_usec
      add :source_id, references(:sources, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:bills, [:jurisdiction_id, :external_id])
    create index(:bills, [:session_id])

    create table(:bill_actions) do
      add :bill_id, references(:bills, on_delete: :delete_all), null: false
      add :actor_body_id, references(:bodies, on_delete: :nilify_all)
      add :position, :integer, null: false
      add :date, :date
      add :description, :text, null: false
      add :raw_type, :string
      add :raw_code, :string
      add :classification, :string
      add :unclassified, :boolean, null: false, default: false
      add :source_id, references(:sources, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:bill_actions, [:bill_id, :position])
    create index(:bill_actions, [:unclassified], where: "unclassified")

    create table(:sponsorships) do
      add :bill_id, references(:bills, on_delete: :delete_all), null: false
      add :person_id, references(:people, on_delete: :delete_all), null: false
      add :classification, :string, null: false
      add :date, :date
      add :withdrawn_on, :date
      add :source_id, references(:sources, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:sponsorships, [:bill_id, :person_id, :classification])
    create index(:sponsorships, [:person_id])

    create table(:bill_versions) do
      add :bill_id, references(:bills, on_delete: :delete_all), null: false
      add :code, :string, null: false
      add :classification, :string
      add :date, :date
      add :xml_url, :text
      add :text_url, :text
      add :xml, :text
      add :xml_schema, :string
      add :plain_text, :text
      add :source_id, references(:sources, on_delete: :restrict), null: false
      add :text_source_id, references(:sources, on_delete: :restrict)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:bill_versions, [:bill_id, :code])
  end
end
