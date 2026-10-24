defmodule EverydayCitizen.Accounts.PasskeysTest do
  use EverydayCitizen.DataCase, async: true

  import EverydayCitizen.AccountsFixtures
  import EverydayCitizen.WebAuthnFixtures

  alias EverydayCitizen.Accounts
  alias EverydayCitizen.Accounts.{Passkeys, UserKey, UserToken}

  setup do
    %{user: user_fixture()}
  end

  defp handle(user), do: Integer.to_string(user.id)

  describe "registration_options/1" do
    test "describes the relying party and user, excluding existing passkeys", %{user: user} do
      {existing, _} = passkey_fixture(user)
      {challenge, options} = Passkeys.registration_options(user)

      assert options.rp == %{id: "localhost", name: "Everyday Citizen"}
      assert options.user.id == Base.url_encode64(handle(user), padding: false)
      assert options.user.name == user.email
      assert options.challenge == Base.url_encode64(challenge.bytes, padding: false)
      assert options.attestation == "none"
      assert options.authenticatorSelection.residentKey == "required"
      assert Enum.map(options.pubKeyCredParams, & &1.alg) == [-7, -257]

      assert options.excludeCredentials == [
               %{
                 type: "public-key",
                 id: Base.url_encode64(existing.credential_id, padding: false)
               }
             ]
    end
  end

  describe "register/4" do
    test "stores a verified passkey with its label, AAGUID and sign count", %{user: user} do
      authenticator = new_authenticator()
      {challenge, _} = Passkeys.registration_options(user)
      response = registration_response(authenticator, challenge.bytes)

      assert {:ok, %UserKey{} = key} = Passkeys.register(user, challenge, response, "Laptop")
      assert key.user_id == user.id
      assert key.label == "Laptop"
      assert key.credential_id == authenticator.credential_id
      assert key.aaguid == authenticator.aaguid
      assert key.sign_count == 0
      assert %{1 => 2, 3 => -7} = Repo.get!(UserKey, key.id).public_key
    end

    test "rejects a response to a different challenge or from another origin", %{user: user} do
      {challenge, _} = Passkeys.registration_options(user)
      other_challenge = registration_response(new_authenticator(), :crypto.strong_rand_bytes(32))

      other_origin =
        registration_response(new_authenticator(), challenge.bytes,
          origin: "https://evil.example"
        )

      for bad <- [other_challenge, other_origin],
          do: assert({:error, :invalid_response} = Passkeys.register(user, challenge, bad, "x"))

      assert Repo.aggregate(UserKey, :count) == 0
    end

    test "garbled payloads return an error instead of raising", %{user: user} do
      {challenge, _} = Passkeys.registration_options(user)
      good = registration_response(new_authenticator(), challenge.bytes)

      for bad <- [
            %{},
            %{good | "attestationObject" => "%%%not base64%%%"},
            %{good | "clientDataJSON" => Base.url_encode64("{not json", padding: false)},
            registration_response(new_authenticator(), challenge.bytes, type: "webauthn.bogus"),
            %{good | "clientDataJSON" => nil}
          ] do
        assert {:error, :invalid_response} = Passkeys.register(user, challenge, bad, "x")
      end
    end

    test "the same authenticator cannot be registered twice", %{user: user} do
      {_key, authenticator} = passkey_fixture(user)
      {challenge, _} = Passkeys.registration_options(user)
      response = registration_response(authenticator, challenge.bytes)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Passkeys.register(user, challenge, response, "Again")

      assert %{credential_id: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "authenticate/2" do
    setup %{user: user} do
      {key, authenticator} = passkey_fixture(user)
      %{key: key, authenticator: authenticator}
    end

    defp sign_in(authenticator, count, opts \\ []) do
      {challenge, options} = Passkeys.authentication_options()

      Passkeys.authenticate(
        challenge,
        assertion_response(authenticator, challenge_bytes(options), count, opts)
      )
    end

    test "returns the user and key, recording use", %{user: user, key: key, authenticator: a} do
      assert {:ok, signed_in, used_key} = sign_in(a, 0)
      assert signed_in.id == user.id
      assert used_key.id == key.id
      assert Repo.get!(UserKey, key.id).last_used_at
    end

    test "accepts a matching user handle and rejects a different one", %{
      user: user,
      authenticator: a
    } do
      assert {:ok, _, _} = sign_in(a, 0, user_handle: handle(user))
      assert {:error, :invalid_response} = sign_in(a, 0, user_handle: handle(user_fixture()))
    end

    test "rejects an unknown passkey and a forged signature", %{authenticator: a} do
      assert {:error, :invalid_response} = sign_in(new_authenticator(), 0)
      forger = %{new_authenticator() | credential_id: a.credential_id}
      assert {:error, :invalid_response} = sign_in(forger, 0)
    end

    @tag :capture_log
    test "a sign count that goes backwards looks like a cloned key", %{key: key, authenticator: a} do
      assert {:ok, _, _} = sign_in(a, 5)
      assert Repo.get!(UserKey, key.id).sign_count == 5
      assert {:error, :invalid_response} = sign_in(a, 3)
      assert {:ok, _, _} = sign_in(a, 6)
    end

    test "authenticators that always report zero keep working", %{authenticator: a} do
      assert {:ok, _, _} = sign_in(a, 0)
      assert {:ok, _, _} = sign_in(a, 0)
    end

    test "a response for an earlier challenge is rejected", %{authenticator: a} do
      {_old, old_options} = Passkeys.authentication_options()
      {challenge, _} = Passkeys.authentication_options()
      response = assertion_response(a, challenge_bytes(old_options), 1)
      assert {:error, :invalid_response} = Passkeys.authenticate(challenge, response)
    end

    test "garbled payloads return an error instead of raising", %{authenticator: a} do
      {challenge, options} = Passkeys.authentication_options()
      good = assertion_response(a, challenge_bytes(options), 1)

      for bad <- [%{}, %{good | "signature" => "%%%"}, %{good | "rawId" => nil}] do
        assert {:error, :invalid_response} = Passkeys.authenticate(challenge, bad)
      end
    end
  end

  describe "list_keys/1 and revoke_key/2" do
    test "lists only the caller's keys", %{user: user} do
      {key, _} = passkey_fixture(user)
      passkey_fixture(user_fixture())
      assert [%UserKey{id: id}] = Passkeys.list_keys(user_scope_fixture(user))
      assert id == key.id
    end

    test "revoking a key deletes it and the sessions started with it", %{user: user} do
      {key, _} = passkey_fixture(user)
      token = Accounts.generate_passkey_login_token(user, key)
      {:ok, signed_in} = Accounts.login_user_by_passkey_token(token)
      session = Accounts.generate_user_session_token(signed_in)

      assert {:ok, %UserKey{}, [%UserToken{}]} =
               Passkeys.revoke_key(user_scope_fixture(user), key.id)

      refute Repo.get(UserKey, key.id)
      refute Accounts.get_user_by_session_token(session)
    end

    test "no one can revoke another person's key", %{user: user} do
      {key, _} = passkey_fixture(user_fixture())
      assert {:error, :not_found} = Passkeys.revoke_key(user_scope_fixture(user), key.id)
      assert {:error, :not_found} = Passkeys.revoke_key(user_scope_fixture(user), "nope")
    end
  end

  describe "passkey sign-in token" do
    test "is single use and carries the passkey into the session", %{user: user} do
      {key, _} = passkey_fixture(user)
      token = Accounts.generate_passkey_login_token(user, key)

      assert {:ok, signed_in} = Accounts.login_user_by_passkey_token(token)
      assert signed_in.session_key_id == key.id
      assert {:error, :invalid} = Accounts.login_user_by_passkey_token(token)
      assert {:error, :invalid} = Accounts.login_user_by_passkey_token("garbage")
    end
  end
end
