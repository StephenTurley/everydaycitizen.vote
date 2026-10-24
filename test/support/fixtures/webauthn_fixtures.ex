defmodule TheFloor.WebAuthnFixtures do
  @moduledoc """
  A software WebAuthn authenticator for tests.

  It holds a real P-256 key pair and builds the exact payloads that
  `assets/js/passkeys.js` sends (base64url, no padding), so tests exercise
  genuine `Wax` verification. Origin and RP ID come from the `:webauthn`
  config, like the server's.
  """

  alias TheFloor.Accounts.Passkeys

  @doc "A fresh authenticator: `%{priv, x, y, credential_id, aaguid}`."
  def new_authenticator do
    {<<4, x::binary-size(32), y::binary-size(32)>>, priv} =
      :crypto.generate_key(:ecdh, :secp256r1)

    %{
      priv: priv,
      x: x,
      y: y,
      credential_id: :crypto.strong_rand_bytes(16),
      aaguid: :crypto.strong_rand_bytes(16)
    }
  end

  @doc """
  The `PasskeyRegister` hook payload for a `navigator.credentials.create`
  answered by `authenticator`. Options: `:origin`, `:type`.
  """
  def registration_response(authenticator, challenge_bytes, opts \\ []) do
    client_data_json = client_data("webauthn.create", challenge_bytes, opts)

    cose_key =
      CBOR.encode(%{
        1 => 2,
        3 => -7,
        -1 => 1,
        -2 => bytes(authenticator.x),
        -3 => bytes(authenticator.y)
      })

    # flags: user present (0x01) | user verified (0x04) | attested data (0x40)
    auth_data =
      rp_id_hash() <>
        <<0x45, 0::32>> <>
        authenticator.aaguid <>
        <<byte_size(authenticator.credential_id)::16>> <>
        authenticator.credential_id <> cose_key

    attestation_object =
      CBOR.encode(%{"fmt" => "none", "attStmt" => %{}, "authData" => bytes(auth_data)})

    %{
      "rawId" => b64(authenticator.credential_id),
      "clientDataJSON" => b64(client_data_json),
      "attestationObject" => b64(attestation_object)
    }
  end

  @doc """
  The `PasskeyLogin` hook payload for a `navigator.credentials.get`
  answered by `authenticator`. Options: `:origin`, `:user_handle` (raw bytes).
  """
  def assertion_response(authenticator, challenge_bytes, sign_count, opts \\ []) do
    client_data_json = client_data("webauthn.get", challenge_bytes, opts)
    # flags: user present | user verified
    auth_data = rp_id_hash() <> <<0x05, sign_count::32>>
    message = auth_data <> :crypto.hash(:sha256, client_data_json)
    signature = :crypto.sign(:ecdsa, :sha256, message, [authenticator.priv, :secp256r1])

    %{
      "rawId" => b64(authenticator.credential_id),
      "clientDataJSON" => b64(client_data_json),
      "authenticatorData" => b64(auth_data),
      "signature" => b64(signature),
      "userHandle" => opts[:user_handle] && b64(opts[:user_handle])
    }
  end

  @doc "Raw challenge bytes from server options (as replied to a hook)."
  def challenge_bytes(%{challenge: c}), do: Base.url_decode64!(c, padding: false)
  def challenge_bytes(%{"challenge" => c}), do: Base.url_decode64!(c, padding: false)

  defp client_data(type, challenge_bytes, opts) do
    Jason.encode!(%{
      type: opts[:type] || type,
      challenge: b64(challenge_bytes),
      origin: opts[:origin] || config(:origin)
    })
  end

  defp rp_id_hash, do: :crypto.hash(:sha256, config(:rp_id))
  defp config(key), do: Application.fetch_env!(:the_floor, :webauthn)[key]
  defp bytes(bin), do: %CBOR.Tag{tag: :bytes, value: bin}
  defp b64(bin), do: Base.url_encode64(bin, padding: false)

  @doc "Registers a software passkey for `user`. Returns `{%UserKey{}, authenticator}`."
  def passkey_fixture(user, label \\ "Test device") do
    authenticator = new_authenticator()
    {challenge, _options} = Passkeys.registration_options(user)
    response = registration_response(authenticator, challenge.bytes)
    {:ok, key} = Passkeys.register(user, challenge, response, label)
    {key, authenticator}
  end
end
