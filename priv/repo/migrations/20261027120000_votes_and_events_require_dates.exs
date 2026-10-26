defmodule EverydayCitizen.Repo.Migrations.VotesAndEventsRequireDates do
  @moduledoc """
  The contract half of 20261026120000: no running code reads `all_day` or
  expects a time on a date-only vote any more. Fills dates for rows written
  by the old code during that deploy, clears the midnight times of sources
  that give only a date, makes the dates required and drops `all_day`.
  """
  use Ecto.Migration

  def up do
    execute """
    UPDATE votes v SET voted_on = ((v.voted_at AT TIME ZONE 'UTC') AT TIME ZONE j.time_zone)::date
    FROM legislative_sessions s JOIN jurisdictions j ON j.id = s.jurisdiction_id
    WHERE s.id = v.session_id AND v.voted_on IS NULL
    """

    execute """
    UPDATE events e SET date = ((e.start_at AT TIME ZONE 'UTC') AT TIME ZONE j.time_zone)::date
    FROM jurisdictions j WHERE j.id = e.jurisdiction_id AND e.date IS NULL
    """

    execute "UPDATE events SET start_at = NULL WHERE all_day"

    # sources that give only a date
    execute """
    UPDATE votes v SET voted_at = NULL FROM sources s
    WHERE s.id = v.source_id AND s.url LIKE 'https://voteview.com/%'
    """

    execute "UPDATE jurisdictions SET time_zone = 'Etc/UTC' WHERE time_zone IS NULL"
    execute "ALTER TABLE jurisdictions ALTER COLUMN time_zone SET NOT NULL"
    execute "ALTER TABLE votes ALTER COLUMN voted_on SET NOT NULL"
    execute "ALTER TABLE events ALTER COLUMN date SET NOT NULL"
    alter table(:events), do: remove(:all_day)
    drop_if_exists index(:events, [:start_at])
  end

  def down do
    create_if_not_exists index(:events, [:start_at])
    alter table(:events), do: add(:all_day, :boolean, default: false, null: false)
    flush()
    execute "UPDATE events SET all_day = true WHERE start_at IS NULL"
    execute "ALTER TABLE events ALTER COLUMN date DROP NOT NULL"
    execute "ALTER TABLE votes ALTER COLUMN voted_on DROP NOT NULL"
    execute "ALTER TABLE jurisdictions ALTER COLUMN time_zone DROP NOT NULL"
  end
end
