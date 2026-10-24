defmodule EverydayCitizen.Repo.Migrations.CreateFollows do
  use Ecto.Migration

  # A person follows a bill or a rep (exactly one), once.
  def change do
    create table(:follows) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :bill_id, references(:bills, on_delete: :delete_all)
      add :person_id, references(:people, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create constraint(:follows, :follows_one_target,
             check: "(bill_id IS NULL) <> (person_id IS NULL)"
           )

    create unique_index(:follows, [:user_id, :bill_id], where: "bill_id IS NOT NULL")
    create unique_index(:follows, [:user_id, :person_id], where: "person_id IS NOT NULL")
    create index(:follows, [:bill_id])
    create index(:follows, [:person_id])
  end
end
