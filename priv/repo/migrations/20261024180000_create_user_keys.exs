defmodule EverydayCitizen.Repo.Migrations.CreateUserKeys do
  use Ecto.Migration

  # Passkeys. A session started with a passkey names it, so revoking the
  # passkey ends those sessions (on delete cascade).
  def change do
    create table(:user_keys) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :credential_id, :binary, null: false
      add :public_key, :binary, null: false
      add :aaguid, :binary
      add :sign_count, :bigint, null: false, default: 0
      add :label, :string, null: false
      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_keys, [:credential_id])
    create index(:user_keys, [:user_id])

    alter table(:users_tokens) do
      add :user_key_id, references(:user_keys, on_delete: :delete_all)
    end

    create index(:users_tokens, [:user_key_id])
  end
end
