defmodule EverydayCitizen.Repo.Migrations.CreateFeedbackReports do
  use Ecto.Migration

  def change do
    create table(:feedback_reports) do
      add :kind, :string, null: false
      add :subject, :string
      add :prompt_version, :string
      add :summary, :text
      add :page, :string
      add :reason, :string, null: false
      add :note, :text
      add :user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime, updated_at: false)
    end
  end
end
