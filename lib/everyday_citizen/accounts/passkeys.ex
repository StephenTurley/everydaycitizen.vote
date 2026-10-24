defmodule EverydayCitizen.Accounts.Passkeys do
  @moduledoc """
  Passkeys (WebAuthn), built directly on `wax_`.

  The browser half is `assets/js/passkeys.js`. Everything on the wire is
  base64url without padding. Callers — LiveViews — keep the `%Wax.Challenge{}`
  in process state between `*_options` and `register/4` / `authenticate/2`;
  only its random bytes ever reach the browser.

  Every verification failure collapses to `{:error, :invalid_response}` so
  the UI cannot be used to learn which passkeys exist.
  """
  import Ecto.Query, warn: false

  require Logger

  alias EverydayCitizen.Accounts.{Scope, User, UserKey, UserToken}
  alias EverydayCitizen.Repo

  @timeout_seconds 300

  ## Registration

  @doc """
  Starts registering a passkey for `user`. Returns `{challenge, options}`:
  keep the challenge, send the options to the `PasskeyRegister` hook. Existing
  passkeys are excluded, so a device that already has one says so instead of
  creating a duplicate.
  """
  def registration_options(%User{} = user) do
    challenge = Wax.new_registration_challenge(wax_opts(attestation: "none"))

    existing =
      Repo.all(from k in UserKey, where: k.user_id == ^user.id, select: k.credential_id)

    options = %{
      challenge: b64(challenge.bytes),
      rp: %{id: challenge.rp_id, name: config(:rp_name)},
      user: %{id: b64(user_handle(user)), name: user.email, displayName: user.email},
      pubKeyCredParams: [%{type: "public-key", alg: -7}, %{type: "public-key", alg: -257}],
      authenticatorSelection: %{
        residentKey: "required",
        requireResidentKey: true,
        userVerification: "preferred"
      },
      attestation: "none",
      excludeCredentials: Enum.map(existing, &%{type: "public-key", id: b64(&1)}),
      timeout: @timeout_seconds * 1000
    }

    {challenge, options}
  end

  @doc """
  Verifies a `PasskeyRegister` payload (`"rawId"`, `"clientDataJSON"`,
  `"attestationObject"`) against `challenge` and stores the passkey.
  """
  def register(%User{} = user, %Wax.Challenge{} = challenge, response, label)
      when is_map(response) do
    with {:ok, attestation_object} <- decode(response["attestationObject"]),
         {:ok, client_data} <- decode(response["clientDataJSON"]),
         {:ok, {auth_data, _attestation}} <-
           safely(fn -> Wax.register(attestation_object, client_data, challenge) end) do
      credential = auth_data.attested_credential_data

      %UserKey{
        user_id: user.id,
        credential_id: credential.credential_id,
        public_key: credential.credential_public_key,
        aaguid: Wax.AuthenticatorData.get_aaguid(auth_data),
        sign_count: auth_data.sign_count
      }
      |> UserKey.create_changeset(%{label: label})
      |> Repo.insert()
    else
      error ->
        Logger.info("Passkey registration rejected for user #{user.id}: #{reason(error)}")

        {:error, :invalid_response}
    end
  end

  ## Authentication

  @doc """
  Starts a passkey sign-in. No allow-list: passkeys are discoverable, so the
  device offers whichever ones it holds for this site.
  """
  def authentication_options do
    challenge = Wax.new_authentication_challenge(wax_opts(user_verification: "preferred"))

    options = %{
      challenge: b64(challenge.bytes),
      rpId: challenge.rp_id,
      userVerification: challenge.user_verification,
      timeout: @timeout_seconds * 1000
    }

    {challenge, options}
  end

  @doc """
  Verifies a `PasskeyLogin` payload (`"rawId"`, `"clientDataJSON"`,
  `"authenticatorData"`, `"signature"`, optional `"userHandle"`). On success
  records the use and returns the active user and the passkey.
  """
  def authenticate(%Wax.Challenge{} = challenge, response) when is_map(response) do
    with {:ok, raw_id} <- decode(response["rawId"]),
         {:ok, auth_data_bin} <- decode(response["authenticatorData"]),
         {:ok, signature} <- decode(response["signature"]),
         {:ok, client_data} <- decode(response["clientDataJSON"]),
         %UserKey{user: %User{} = user} = key <- get_key(raw_id),
         :ok <- check_user_handle(response["userHandle"], user),
         {:ok, auth_data} <-
           safely(fn ->
             Wax.authenticate(raw_id, auth_data_bin, signature, client_data, challenge, [
               {key.credential_id, key.public_key}
             ])
           end),
         :ok <- check_sign_count(key, auth_data.sign_count),
         {:ok, key} <- record_use(key, auth_data.sign_count) do
      {:ok, user, key}
    else
      error ->
        Logger.info("Passkey sign-in rejected: #{reason(error)}")

        {:error, :invalid_response}
    end
  end

  defp get_key(credential_id) do
    Repo.one(from k in UserKey, where: k.credential_id == ^credential_id, preload: [:user])
  end

  defp check_user_handle(nil, _user), do: :ok

  defp check_user_handle(handle, %User{id: id}) do
    if decode(handle) == {:ok, user_handle(%User{id: id})}, do: :ok, else: {:error, :user_handle}
  end

  # Authenticators that keep a counter must move it forward; one that goes
  # backwards suggests a cloned key. Synced passkeys (iCloud, Google) always
  # report 0, which is allowed.
  defp check_sign_count(%UserKey{sign_count: stored} = key, new)
       when stored > 0 and new <= stored do
    Logger.warning(
      "Passkey #{key.id} of user #{key.user_id}: counter went backwards; possible cloned key"
    )

    {:error, :sign_count}
  end

  defp check_sign_count(_key, _new), do: :ok

  defp record_use(key, sign_count) do
    key
    |> Ecto.Changeset.change(sign_count: sign_count, last_used_at: DateTime.utc_now(:second))
    |> Repo.update()
  end

  ## Management

  @doc "The caller's passkeys, most recently used first."
  def list_keys(%Scope{user: %User{id: user_id}}) do
    Repo.all(
      from k in UserKey,
        where: k.user_id == ^user_id,
        order_by: [desc_nulls_last: k.last_used_at, desc: k.inserted_at]
    )
  end

  @doc """
  Revokes one of the caller's passkeys. Sessions started with it are deleted
  with it (database cascade) and returned so the caller can disconnect them.
  """
  def revoke_key(%Scope{user: %User{id: user_id}}, key_id) do
    with {id, ""} <- Integer.parse(to_string(key_id)),
         %UserKey{} = key <-
           Repo.one(from k in UserKey, where: k.id == ^id and k.user_id == ^user_id) do
      delete_with_sessions(key)
    else
      _ -> {:error, :not_found}
    end
  end

  defp delete_with_sessions(key) do
    Repo.transact(fn ->
      sessions = Repo.all_by(UserToken, user_key_id: key.id, context: "session")

      with {:ok, key} <- Repo.delete(key), do: {:ok, {key, sessions}}
    end)
    |> case do
      {:ok, {key, sessions}} -> {:ok, key, sessions}
      error -> error
    end
  end

  ## Helpers

  # Wax raises on some malformed input (e.g. an unknown client data type);
  # a hostile or garbled payload must never crash the LiveView.
  defp safely(fun) do
    fun.()
  rescue
    error -> {:error, error}
  end

  defp decode(value) when is_binary(value), do: Base.url_decode64(value, padding: false)
  defp decode(_), do: :error

  defp b64(bin), do: Base.url_encode64(bin, padding: false)

  defp wax_opts(extra) do
    [origin: config(:origin), rp_id: config(:rp_id), timeout: @timeout_seconds] ++ extra
  end

  defp config(key), do: Application.fetch_env!(:everyday_citizen, :webauthn)[key]

  # The WebAuthn user handle: the account id, never the email.
  defp user_handle(%User{id: id}), do: Integer.to_string(id)

  defp reason({:error, %{__exception__: true} = e}), do: Exception.message(e)
  defp reason(other), do: inspect(other)
end
