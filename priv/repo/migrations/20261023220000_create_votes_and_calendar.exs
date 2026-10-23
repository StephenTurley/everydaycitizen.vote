defmodule TheFloor.Repo.Migrations.CreateVotesAndCalendar do
  use Ecto.Migration

  def change do
    create table(:votes) do
      add :body_id, references(:bodies, on_delete: :delete_all), null: false
      add :session_id, references(:legislative_sessions, on_delete: :delete_all), null: false
      add :bill_id, references(:bills, on_delete: :nilify_all)
      add :external_id, :string, null: false
      add :identifier, :string
      add :question, :text
      add :result, :string
      add :passed, :boolean
      add :voted_at, :utc_datetime_usec, null: false
      add :yea_count, :integer, null: false, default: 0
      add :nay_count, :integer, null: false, default: 0
      add :present_count, :integer, null: false, default: 0
      add :absent_count, :integer, null: false, default: 0
      add :source_id, references(:sources, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:votes, [:body_id, :session_id, :external_id])
    create index(:votes, [:bill_id])

    create table(:vote_positions) do
      add :vote_id, references(:votes, on_delete: :delete_all), null: false
      add :person_id, references(:people, on_delete: :nilify_all)
      add :raw_label, :string
      add :option, :string, null: false
      add :raw_option, :string
      add :source_id, references(:sources, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:vote_positions, [:vote_id])
    create index(:vote_positions, [:person_id])

    create table(:events) do
      add :jurisdiction_id, references(:jurisdictions, on_delete: :delete_all), null: false
      add :body_id, references(:bodies, on_delete: :nilify_all)
      add :external_id, :string, null: false
      add :classification, :string, null: false
      add :raw_classification, :string
      add :status, :string, null: false, default: "scheduled"
      add :title, :text
      add :start_at, :utc_datetime_usec, null: false
      add :all_day, :boolean, null: false, default: false
      add :location, :string
      add :unresolved_bill_labels, {:array, :string}, null: false, default: []
      add :source_id, references(:sources, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:events, [:jurisdiction_id, :external_id])
    create index(:events, [:start_at])

    create table(:event_bills) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :bill_id, references(:bills, on_delete: :delete_all), null: false
      add :source_id, references(:sources, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:event_bills, [:event_id, :bill_id])
    create index(:event_bills, [:bill_id])
  end
end
