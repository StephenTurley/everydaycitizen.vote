defmodule EverydayCitizen.Repo.Migrations.AddBillSearchIndexes do
  use Ecto.Migration

  # built concurrently so the tables stay writable while the indexes build
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # full-text search over each version's text
    create_concurrently("bill_versions_text_search", """
    ON bill_versions USING gin (to_tsvector('english', plain_text)) WHERE plain_text IS NOT NULL
    """)

    # a bill number typed any way ("H.R. 22", "hr22") matches this key
    create_concurrently("bills_identifier_key", """
    ON bills (lower(regexp_replace(identifier, '[^A-Za-z0-9]', '', 'g')))
    """)
  end

  def down do
    execute "DROP INDEX CONCURRENTLY IF EXISTS bills_identifier_key"
    execute "DROP INDEX CONCURRENTLY IF EXISTS bill_versions_text_search"
  end

  # A failed concurrent build leaves an INVALID index behind, which IF NOT
  # EXISTS would silently keep; drop it so the build runs again.
  defp create_concurrently(name, definition) do
    %{rows: rows} =
      repo().query!(
        """
        SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
        WHERE c.relname = $1 AND NOT i.indisvalid
        """,
        [name]
      )

    if rows != [], do: execute("DROP INDEX CONCURRENTLY IF EXISTS #{name}")
    execute "CREATE INDEX CONCURRENTLY IF NOT EXISTS #{name} #{definition}"
  end
end
