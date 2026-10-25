defmodule EverydayCitizen.Repo.Migrations.AddBillActionsBecameLawIndex do
  use Ecto.Migration

  # built concurrently so bill_actions stays writable while the index builds
  @disable_ddl_transaction true
  @disable_migration_lock true

  # the home page's newest laws read only these rows
  def change do
    create index(:bill_actions, [:bill_id, :date],
             where: "classification = 'became_law'",
             concurrently: true
           )
  end
end
