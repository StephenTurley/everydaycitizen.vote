defmodule EverydayCitizen.Accounts.UserKey do
  @moduledoc """
  A registered passkey, shown to people by its label ("This device, Oct 24").
  Crypto fields are set from a verified WebAuthn response, never cast from
  params.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias EverydayCitizen.Accounts.{CoseKey, User}

  schema "user_keys" do
    field :credential_id, :binary
    field :public_key, CoseKey, redact: true
    field :aaguid, :binary
    field :sign_count, :integer, default: 0
    field :label, :string
    field :last_used_at, :utc_datetime

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for a freshly verified passkey; only the label comes from the person."
  def create_changeset(key, attrs) do
    key
    |> cast(attrs, [:label])
    |> update_change(:label, &String.trim/1)
    |> validate_required([:label])
    |> validate_length(:label, max: 60)
    |> unique_constraint(:credential_id)
  end
end
