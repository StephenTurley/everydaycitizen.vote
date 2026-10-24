defmodule EverydayCitizen.Repo.Migrations.AddVoteClassification do
  use Ecto.Migration

  def change do
    alter table(:votes) do
      add :classification, :string, null: false, default: "other"
    end

    create index(:votes, [:bill_id, :classification])
  end
end
