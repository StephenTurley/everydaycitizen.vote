defmodule EverydayCitizen.Repo.Migrations.AddBillsWebUrl do
  use Ecto.Migration

  # The bill's official page for people (the source URL may be an API).
  def change do
    alter table(:bills) do
      add :web_url, :string
    end
  end
end
