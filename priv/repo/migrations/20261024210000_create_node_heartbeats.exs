defmodule EverydayCitizen.Repo.Migrations.CreateNodeHeartbeats do
  use Ecto.Migration

  # Each running app node (Oban's node name) records that it is alive, so jobs
  # left executing by a node that stopped (a deploy, a crash) can be released.
  def change do
    create table(:node_heartbeats, primary_key: false) do
      add :node, :string, primary_key: true
      add :seen_at, :utc_datetime_usec, null: false
    end
  end
end
