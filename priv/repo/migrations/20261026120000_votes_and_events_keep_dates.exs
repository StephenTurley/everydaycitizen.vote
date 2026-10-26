defmodule EverydayCitizen.Repo.Migrations.VotesAndEventsKeepDates do
  @moduledoc """
  A vote or event keeps the legislature's own date (`voted_on`, `date`) and a
  time (`voted_at`, `start_at`) only when its source gave one. Dates were
  stored as midnight in the legislature's zone; each jurisdiction now records
  that zone.
  """
  use Ecto.Migration

  def up do
    alter table(:jurisdictions), do: add(:time_zone, :string)
    flush()
    # the only jurisdiction stored so far; its adapter writes the same value
    execute "UPDATE jurisdictions SET time_zone = 'America/New_York' WHERE key = 'federal'"
    execute "UPDATE jurisdictions SET time_zone = 'Etc/UTC' WHERE time_zone IS NULL"
    execute "ALTER TABLE jurisdictions ALTER COLUMN time_zone SET NOT NULL"

    alter table(:votes), do: add(:voted_on, :date)
    alter table(:events), do: add(:date, :date)
    flush()

    execute """
    UPDATE votes v SET voted_on = ((v.voted_at AT TIME ZONE 'UTC') AT TIME ZONE j.time_zone)::date
    FROM legislative_sessions s JOIN jurisdictions j ON j.id = s.jurisdiction_id
    WHERE s.id = v.session_id
    """

    # sources that give only a date
    execute "ALTER TABLE votes ALTER COLUMN voted_at DROP NOT NULL"

    execute """
    UPDATE votes v SET voted_at = NULL FROM sources s
    WHERE s.id = v.source_id AND s.url LIKE 'https://voteview.com/%'
    """

    execute """
    UPDATE events e SET date = ((e.start_at AT TIME ZONE 'UTC') AT TIME ZONE j.time_zone)::date
    FROM jurisdictions j WHERE j.id = e.jurisdiction_id
    """

    execute "ALTER TABLE votes ALTER COLUMN voted_on SET NOT NULL"
    execute "ALTER TABLE events ALTER COLUMN start_at DROP NOT NULL"
    execute "UPDATE events SET start_at = NULL WHERE all_day"
    execute "ALTER TABLE events ALTER COLUMN date SET NOT NULL"

    alter table(:events), do: remove(:all_day)
    create index(:votes, [:voted_on])
    create index(:events, [:jurisdiction_id, :date])
  end

  def down do
    alter table(:events), do: add(:all_day, :boolean, default: false, null: false)
    flush()

    execute """
    UPDATE events e SET all_day = true,
      start_at = (e.date::timestamp AT TIME ZONE j.time_zone) AT TIME ZONE 'UTC'
    FROM jurisdictions j WHERE j.id = e.jurisdiction_id AND e.start_at IS NULL
    """

    execute """
    UPDATE votes v SET voted_at = (v.voted_on::timestamp AT TIME ZONE j.time_zone) AT TIME ZONE 'UTC'
    FROM legislative_sessions s JOIN jurisdictions j ON j.id = s.jurisdiction_id
    WHERE s.id = v.session_id AND v.voted_at IS NULL
    """

    execute "ALTER TABLE votes ALTER COLUMN voted_at SET NOT NULL"
    execute "ALTER TABLE events ALTER COLUMN start_at SET NOT NULL"
    drop index(:events, [:jurisdiction_id, :date])
    drop index(:votes, [:voted_on])
    alter table(:events), do: remove(:date)
    alter table(:votes), do: remove(:voted_on)
    alter table(:jurisdictions), do: remove(:time_zone)
  end
end
