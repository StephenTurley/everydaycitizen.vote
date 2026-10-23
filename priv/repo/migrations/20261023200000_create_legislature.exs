defmodule TheFloor.Repo.Migrations.CreateLegislature do
  use Ecto.Migration

  def change do
    create table(:jurisdictions) do
      add :key, :string, null: false
      add :name, :string, null: false
      add :classification, :string, null: false
      add :source_id, references(:sources, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:jurisdictions, [:key])

    create table(:bodies) do
      add :jurisdiction_id, references(:jurisdictions, on_delete: :delete_all), null: false
      add :parent_id, references(:bodies, on_delete: :nilify_all)
      add :external_id, :string, null: false
      add :name, :string, null: false
      add :classification, :string, null: false
      add :source_id, references(:sources, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:bodies, [:jurisdiction_id, :external_id])
    create index(:bodies, [:parent_id])

    create table(:legislative_sessions) do
      add :jurisdiction_id, references(:jurisdictions, on_delete: :delete_all), null: false
      add :parent_id, references(:legislative_sessions, on_delete: :nilify_all)
      add :identifier, :string, null: false
      add :name, :string
      add :start_date, :date
      add :end_date, :date
      add :source_id, references(:sources, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:legislative_sessions, [:jurisdiction_id, :identifier])
    create index(:legislative_sessions, [:parent_id])

    create table(:people) do
      add :name, :string, null: false
      add :given_name, :string
      add :family_name, :string
      add :image_url, :text
      add :source_id, references(:sources, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:person_identifiers) do
      add :person_id, references(:people, on_delete: :delete_all), null: false
      add :scheme, :string, null: false
      add :value, :string, null: false
      add :source_id, references(:sources, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:person_identifiers, [:scheme, :value])
    create index(:person_identifiers, [:person_id])

    create table(:memberships) do
      add :person_id, references(:people, on_delete: :delete_all), null: false
      add :body_id, references(:bodies, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :party, :string
      add :district, :string
      add :start_date, :date
      add :end_date, :date
      add :source_id, references(:sources, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    # Committee memberships arrive without dates, so NULLs must collide (R3).
    create unique_index(:memberships, [:person_id, :body_id, :role, :start_date],
             nulls_distinct: false
           )

    create index(:memberships, [:body_id])
  end
end
