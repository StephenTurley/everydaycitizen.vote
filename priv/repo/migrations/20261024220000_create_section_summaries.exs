defmodule EverydayCitizen.Repo.Migrations.CreateSectionSummaries do
  use Ecto.Migration

  # Plain-English summaries of bill sections, written by an LLM the first time
  # a section is opened. Provenance: the version and section, the hash of the
  # exact text summarized, the model and the prompt version.
  def change do
    create table(:section_summaries) do
      add :bill_version_id, references(:bill_versions, on_delete: :delete_all), null: false
      add :section_index, :integer, null: false
      add :prompt_version, :string, null: false
      add :model, :string, null: false
      add :source_hash, :binary, null: false
      add :summary, :text, null: false
      add :input_tokens, :integer
      add :output_tokens, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:section_summaries, [:bill_version_id, :section_index, :prompt_version])
    create index(:section_summaries, [:inserted_at])
  end
end
