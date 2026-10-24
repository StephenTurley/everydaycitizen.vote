defmodule EverydayCitizen.Repo.Migrations.AddBillVersionSectionsVersion do
  use Ecto.Migration

  # Which section-splitter output shape `sections` holds; null for versions
  # split before it was recorded, so they are split again.
  def change do
    alter table(:bill_versions) do
      add :sections_version, :integer
    end
  end
end
