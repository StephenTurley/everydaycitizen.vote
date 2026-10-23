defmodule TheFloor.Repo.Migrations.AddVoteRefs do
  use Ecto.Migration

  # The source's references, kept so a vote ingested before its bill or people can
  # be linked later (TheFloor.Ingest.Relink).
  def change do
    alter table(:votes) do
      add :bill_ref, :string
    end

    alter table(:vote_positions) do
      add :person_scheme, :string
      add :person_value, :string
    end

    create index(:votes, [:bill_ref], where: "bill_id IS NULL AND bill_ref IS NOT NULL")

    create index(:vote_positions, [:person_scheme, :person_value],
             where: "person_id IS NULL AND person_value IS NOT NULL"
           )
  end
end
