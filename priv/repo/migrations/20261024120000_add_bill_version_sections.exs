defmodule TheFloor.Repo.Migrations.AddBillVersionSections do
  use Ecto.Migration

  def change do
    alter table(:bill_versions) do
      add :sections, :jsonb
    end
  end
end
