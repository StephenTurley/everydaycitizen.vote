defmodule EverydayCitizen.Repo.Migrations.AddDistrictMapToPostalDistricts do
  use Ecto.Migration

  # The district map the rows came from; rows without one are not used until
  # the file is loaded again.
  def change do
    alter table(:postal_districts) do
      add :district_map, :string
    end
  end
end
