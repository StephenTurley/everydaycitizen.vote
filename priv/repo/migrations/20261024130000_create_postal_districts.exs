defmodule EverydayCitizen.Repo.Migrations.CreatePostalDistricts do
  use Ecto.Migration

  def change do
    create table(:postal_districts) do
      add :jurisdiction_id, references(:jurisdictions, on_delete: :delete_all), null: false
      add :postal_code, :string, null: false
      add :district_key, :string, null: false
      add :land_share, :float, null: false
      add :source_id, references(:sources, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:postal_districts, [:jurisdiction_id, :postal_code, :district_key])
  end
end
