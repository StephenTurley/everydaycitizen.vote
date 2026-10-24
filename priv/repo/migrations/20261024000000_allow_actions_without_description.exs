defmodule EverydayCitizen.Repo.Migrations.AllowActionsWithoutDescription do
  use Ecto.Migration

  # Some source actions carry only a date and a code; they are kept as given.
  def change do
    alter table(:bill_actions) do
      modify :description, :text, null: true, from: {:text, null: false}
    end
  end
end
