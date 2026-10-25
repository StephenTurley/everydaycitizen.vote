defmodule EverydayCitizen.Repo.Migrations.CreateBillTitlesAndSearchKeys do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"

    # every title a bill has: official, short, popular, and those of its parts
    # (the display title stays on bills.title)
    create table(:bill_titles) do
      add :bill_id, references(:bills, on_delete: :delete_all), null: false
      add :title, :text, null: false
      add :kind, :string, null: false
      add :source_id, references(:sources, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:bill_titles, [:bill_id])

    # the one rule for comparing names: lower-case, runs of non-alphanumerics
    # become one space, trim, drop a trailing " of <year>" and a trailing " act"
    execute """
    CREATE FUNCTION ec_name_key(text) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
      SELECT btrim(
        regexp_replace(
          regexp_replace(
            btrim(regexp_replace(lower($1), '[^[:alnum:]]+', ' ', 'g')),
            ' of [0-9]{4}$', ''),
          ' act$', ''))
    $$
    """

    execute "CREATE INDEX bill_titles_name_key_trgm ON bill_titles USING gin (ec_name_key(title) gin_trgm_ops)"

    execute "CREATE INDEX bills_name_key_trgm ON bills USING gin (ec_name_key(title) gin_trgm_ops)"

    execute "CREATE INDEX people_name_key_trgm ON people USING gin (ec_name_key(name) gin_trgm_ops)"
  end

  def down do
    execute "DROP INDEX people_name_key_trgm"
    execute "DROP INDEX bills_name_key_trgm"
    execute "DROP INDEX bill_titles_name_key_trgm"
    execute "DROP FUNCTION ec_name_key(text)"
    drop table(:bill_titles)
    execute "DROP EXTENSION IF EXISTS pg_trgm"
  end
end
