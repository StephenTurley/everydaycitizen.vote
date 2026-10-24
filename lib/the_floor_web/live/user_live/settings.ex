defmodule TheFloorWeb.UserLive.Settings do
  @moduledoc """
  The account page: passkeys (add one on this device, remove any), the email,
  and signing out. Changing the email needs a recent sign-in (sudo mode); the
  rest of the page does not.
  """
  use TheFloorWeb, :live_view

  alias TheFloor.Accounts
  alias TheFloor.Accounts.Passkeys
  alias TheFloorWeb.{PasskeyMessages, UserAuth}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="pt-10 pb-4 flex flex-col gap-1">
        <h1 class="m-0 text-[28px] leading-tight font-bold tracking-tight">Your account</h1>
        <p class="m-0 text-[15px] text-floor-muted">{@current_email}</p>
      </section>

      <section aria-label="Passkeys" class="pb-6 flex flex-col gap-2.5">
        <h2 class="m-0 text-[18px] font-bold">Passkeys</h2>
        <p class="m-0 text-[14px] leading-relaxed text-floor-ink-2">
          A passkey signs you in on this device with your fingerprint, face or screen lock,
          without waiting for an email.
        </p>
        <p :if={@passkeys == []} class="m-0 text-[15px] text-floor-muted">No passkeys yet.</p>
        <ul :if={@passkeys != []} id="passkeys" class="m-0 p-0 list-none flex flex-col gap-2">
          <li
            :for={key <- @passkeys}
            id={"passkey-#{key.id}"}
            class="flex items-center justify-between gap-3 px-3.5 py-3 rounded-xl bg-floor-card border border-floor-line"
          >
            <span class="flex flex-col gap-0.5">
              <span class="text-[15px] font-semibold">{key.label}</span>
              <span class="text-[13px] text-floor-muted">
                {if key.last_used_at,
                  do: "Last used #{Calendar.strftime(key.last_used_at, "%b %-d, %Y")}",
                  else: "Not used yet"}
              </span>
            </span>
            <button
              type="button"
              phx-click="remove_passkey"
              phx-value-id={key.id}
              data-confirm="Remove this passkey? You can still sign in by email."
              class="px-3 py-2 text-[14px] font-semibold text-floor-accent"
            >
              Remove
            </button>
          </li>
        </ul>
        <button
          :if={@passkeys_supported}
          type="button"
          id="passkey-add"
          phx-hook="PasskeyRegister"
          class="self-start px-4 py-2.5 rounded-xl bg-floor-card border border-floor-line text-[15px] font-semibold text-floor-ink"
        >
          Add a passkey on this device
        </button>
        <p :if={!@passkeys_supported} class="m-0 text-[14px] text-floor-muted">
          This browser can't use passkeys. You can still sign in by email.
        </p>
      </section>

      <section aria-label="Email" class="pb-6 flex flex-col gap-2">
        <h2 class="m-0 text-[18px] font-bold">Email</h2>
        <.form
          :if={@sudo}
          for={@email_form}
          id="email_form"
          phx-submit="update_email"
          phx-change="validate_email"
          class="flex flex-col gap-2"
        >
          <label for="user_email" class="text-[13px] font-semibold text-floor-muted">
            New email
          </label>
          <input
            type="email"
            id="user_email"
            name={@email_form[:email].name}
            value={@email_form[:email].value}
            autocomplete="username"
            spellcheck="false"
            required
            class="text-[16px] px-3 py-3 rounded-xl border border-[#b8bdc4] bg-floor-card"
          />
          <p :for={{msg, _} <- @email_form[:email].errors} class="m-0 text-[14px]" role="alert">
            Email {msg}.
          </p>
          <button
            type="submit"
            phx-disable-with="Sending…"
            class="self-start px-4 py-2.5 rounded-xl bg-floor-ink text-white text-[15px] font-semibold"
          >
            Change email
          </button>
        </.form>
        <p :if={!@sudo} class="m-0 text-[15px] text-floor-ink-2">
          To change your email,
          <.link navigate={~p"/users/log-in"} class="font-semibold text-floor-accent">confirm it's you</.link>
          first.
        </p>
      </section>

      <.link
        href={~p"/users/log-out"}
        method="delete"
        class="inline-block py-2 text-[15px] font-semibold text-floor-accent"
      >
        Sign out
      </.link>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed.")

        {:error, _} ->
          put_flash(socket, :error, "That email change link is invalid or has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     assign(socket,
       page_title: "Your account",
       current_email: user.email,
       sudo: Accounts.sudo_mode?(user, -10),
       passkeys: Passkeys.list_keys(socket.assigns.current_scope),
       passkeys_supported: true,
       passkey_challenge: nil,
       email_form: to_form(Accounts.change_user_email(user, %{}, validate_unique: false))
     )}
  end

  @impl true
  def handle_event("passkey:register_options", _params, socket) do
    {challenge, options} = Passkeys.registration_options(socket.assigns.current_scope.user)
    {:reply, options, assign(socket, :passkey_challenge, challenge)}
  end

  def handle_event("passkey:register", params, %{assigns: %{passkey_challenge: nil}} = socket),
    do: passkey_registered(socket, params, {:error, :invalid_response})

  def handle_event("passkey:register", params, socket) do
    user = socket.assigns.current_scope.user
    label = "Added #{Calendar.strftime(Date.utc_today(), "%b %-d, %Y")}"
    result = Passkeys.register(user, socket.assigns.passkey_challenge, params, label)
    passkey_registered(assign(socket, :passkey_challenge, nil), params, result)
  end

  def handle_event("passkey:error", params, socket),
    do: {:noreply, put_flash(socket, :error, PasskeyMessages.client_error(params["name"]))}

  def handle_event("passkey:unsupported", _params, socket),
    do: {:noreply, assign(socket, :passkeys_supported, false)}

  def handle_event("remove_passkey", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    case Passkeys.revoke_key(scope, id) do
      {:ok, _key, sessions} ->
        # sessions started with this passkey end, this one included if it was
        UserAuth.disconnect_sessions(sessions)

        {:noreply,
         socket
         |> assign(:passkeys, Passkeys.list_keys(scope))
         |> put_flash(:info, "Passkey removed.")}

      {:error, :not_found} ->
        {:noreply, assign(socket, :passkeys, Passkeys.list_keys(scope))}
    end
  end

  def handle_event("validate_email", %{"user" => user_params}, socket) do
    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", %{"user" => user_params}, socket) do
    user = socket.assigns.current_scope.user

    with true <- Accounts.sudo_mode?(user, -10),
         %{valid?: true} = changeset <- Accounts.change_user_email(user, user_params) do
      Accounts.deliver_user_update_email_instructions(
        Ecto.Changeset.apply_action!(changeset, :insert),
        user.email,
        &url(~p"/users/settings/confirm-email/#{&1}")
      )

      {:noreply, put_flash(socket, :info, "We sent a link to the new address to confirm it.")}
    else
      false -> {:noreply, push_navigate(socket, to: ~p"/users/log-in")}
      changeset -> {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  defp passkey_registered(socket, _params, {:ok, _key}) do
    {:noreply,
     socket
     |> assign(:passkeys, Passkeys.list_keys(socket.assigns.current_scope))
     |> put_flash(:info, "Passkey added.")}
  end

  defp passkey_registered(socket, _params, {:error, %Ecto.Changeset{}}),
    do: {:noreply, put_flash(socket, :error, PasskeyMessages.client_error("InvalidStateError"))}

  defp passkey_registered(socket, _params, {:error, _}),
    do: {:noreply, put_flash(socket, :error, PasskeyMessages.failed())}
end
