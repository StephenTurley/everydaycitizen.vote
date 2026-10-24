defmodule EverydayCitizen.Repo.Migrations.RenameObanJobWorkers do
  use Ecto.Migration

  # The code was renamed from TheFloor to EverydayCitizen; Oban stores each
  # job's worker module by name, so unfinished jobs must name the new modules.
  @states "('available', 'scheduled', 'retryable', 'executing')"

  def up do
    execute """
    UPDATE oban_jobs SET worker = regexp_replace(worker, '^TheFloor\\.', 'EverydayCitizen.')
    WHERE state IN #{@states}
    """
  end

  def down do
    execute """
    UPDATE oban_jobs SET worker = regexp_replace(worker, '^EverydayCitizen\\.', 'TheFloor.')
    WHERE state IN #{@states}
    """
  end
end
