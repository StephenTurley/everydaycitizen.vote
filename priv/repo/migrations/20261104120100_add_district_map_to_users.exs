defmodule EverydayCitizen.Repo.Migrations.AddDistrictMapToUsers do
  use Ecto.Migration

  # The district map a saved district was found on (`Reps.district_map/0`).
  def change do
    alter table(:users) do
      add :district_map, :string
    end
  end
end
