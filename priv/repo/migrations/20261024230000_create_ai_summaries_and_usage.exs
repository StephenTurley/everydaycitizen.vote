defmodule EverydayCitizen.Repo.Migrations.CreateAiSummariesAndUsage do
  use Ecto.Migration

  # Bill executive summaries and weekly rep summaries (keyed by kind, subject and
  # prompt version, shown while the input still hashes the same), and the cost
  # of every Claude call, for the daily spending budget.
  def change do
    create table(:ai_summaries) do
      add :kind, :string, null: false
      add :subject, :string, null: false
      add :prompt_version, :string, null: false
      add :model, :string, null: false
      add :source_hash, :binary, null: false
      add :summary, :text, null: false
      add :input_tokens, :integer
      add :output_tokens, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ai_summaries, [:kind, :subject, :prompt_version])

    create table(:ai_usage) do
      add :kind, :string, null: false
      add :input_tokens, :integer, null: false, default: 0
      add :output_tokens, :integer, null: false, default: 0
      add :cost_micros, :bigint, null: false, default: 0

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:ai_usage, [:inserted_at])
  end
end
