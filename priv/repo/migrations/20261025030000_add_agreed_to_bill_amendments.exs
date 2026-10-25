defmodule EverydayCitizen.Repo.Migrations.AddAgreedToBillAmendments do
  use Ecto.Migration

  def change do
    alter table(:bill_amendments) do
      # whether it was agreed to (only those changed the text)
      add :agreed, :boolean, null: false, default: false
    end
  end
end
