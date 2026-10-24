defmodule EverydayCitizenWeb.UserLive.Login do
  @moduledoc """
  Sign in with a passkey (button or the email field's autofill), or sign in or
  create an account by emailed link: there are no passwords. An
  email with no account gets one (unconfirmed until the link is used). The reply
  is the same either way, so the page does not reveal who has an account.
  Signed in, it re-confirms the person for sensitive changes.
  """
  use EverydayCitizenWeb, :live_view

  alias EverydayCitizen.Accounts
  alias EverydayCitizen.Accounts.Passkeys
  alias EverydayCitizenWeb.PasskeyMessages

  @hour :timer.hours(1)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="pt-10 pb-4 flex flex-col gap-3">
        <h1 class="m-0 text-[28px] leading-tight font-bold tracking-tight">
          {if @current_scope, do: "Confirm it's you", else: "Sign in"}
        </h1>
        <p class="m-0 text-[15px] leading-relaxed text-floor-ink-2">
          <%= if @current_scope do %>
            We'll email you a link to confirm before changing your account.
          <% else %>
            Enter your email and we'll send you a link to sign in. New here? The same link
            creates your account. An account lets you follow bills and your reps.
          <% end %>
        </p>
      </section>

      <div id="passkey-login" phx-hook="PasskeyLogin" class="flex flex-col gap-3">
        <div :if={@passkeys_supported and is_nil(@current_scope)} class="flex flex-col gap-3">
          <button
            type="button"
            id="passkey-sign-in"
            data-passkey-button
            class="py-3 rounded-xl bg-floor-card border border-floor-line text-[16px] font-semibold text-floor-ink"
          >
            Sign in with a passkey
          </button>
          <p class="m-0 text-center text-[13px] text-floor-muted">or get a link by email</p>
        </div>
      </div>

      <.form
        for={@passkey_form}
        id="passkey_login_form"
        action={~p"/users/log-in"}
        phx-trigger-action={@passkey_trigger}
      >
        <input type="hidden" name={@passkey_form[:token].name} value={@passkey_form[:token].value} />
      </.form>

      <p :if={local_mail_adapter?()} class="m-0 mb-3 text-[13px] text-floor-muted">
        Development: sent emails appear in <.link href="/dev/mailbox" class="underline">the mailbox</.link>.
      </p>

      <.form
        :let={f}
        for={@form}
        id="login_form_magic"
        action={~p"/users/log-in"}
        phx-submit="submit_magic"
        class="flex flex-col gap-2"
      >
        <label for="user_email" class="text-[13px] font-semibold text-floor-muted">Email</label>
        <input
          type="email"
          id="user_email"
          name={f[:email].name}
          value={f[:email].value}
          readonly={!!@current_scope}
          autocomplete="username webauthn"
          spellcheck="false"
          required
          phx-mounted={JS.focus()}
          class="text-[16px] px-3 py-3 rounded-xl border border-[#b8bdc4] bg-floor-card"
        />
        <p :for={msg <- @errors} class="m-0 text-[14px] text-floor-ink" role="alert">{msg}</p>
        <button
          type="submit"
          phx-disable-with="Sending…"
          class="mt-1 py-3 rounded-xl bg-floor-ink text-white text-[16px] font-semibold"
        >
          Email me a link
        </button>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      assign(socket, :remote_ip, EverydayCitizenWeb.RemoteIp.from_socket(socket))

    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    {:ok,
     assign(socket,
       form: to_form(%{"email" => email}, as: "user"),
       errors: [],
       passkey_form: to_form(%{"token" => nil}, as: "passkey"),
       passkey_trigger: false,
       passkey_challenges: %{},
       passkeys_supported: true
     )}
  end

  # Each request keeps its own challenge: the email field's autofill
  # ("autofill") and the button ("button"), fetched before the tap because
  # Safari only shows its passkey sheet for a request started inside the tap.
  @impl true
  def handle_event("passkey:auth_options", params, socket) do
    for = request_for(params)
    {challenge, options} = Passkeys.authentication_options()

    {:reply, Map.put(options, :for, for),
     update(socket, :passkey_challenges, &Map.put(&1, for, challenge))}
  end

  def handle_event("passkey:auth", params, socket) do
    {challenge, challenges} = Map.pop(socket.assigns.passkey_challenges, request_for(params))
    authenticate(assign(socket, :passkey_challenges, challenges), challenge, params)
  end

  def handle_event("passkey:error", params, socket),
    do: {:noreply, put_flash(socket, :error, PasskeyMessages.client_error(params["name"]))}

  def handle_event("passkey:unsupported", _params, socket),
    do: {:noreply, assign(socket, :passkeys_supported, false)}

  # Limits (ten requests an hour per visitor, one link a minute and five an
  # hour per account) answer exactly like a sent link, so the reply never
  # reveals who has an account; a failed send says so and reaches Sentry.
  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    with :ok <- EverydayCitizen.RateLimit.hit({:login_link, socket.assigns.remote_ip}, 10, @hour),
         {:ok, user} <- user_for(String.trim(email)),
         true <- Accounts.login_link_allowed?(user),
         {:ok, _email} <- Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}")) do
      sent(socket)
    else
      limited when limited in [:limited, false] ->
        sent(socket)

      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          for {msg, _opts} <- Keyword.get_values(changeset.errors, :email), do: "Email #{msg}."

        {:noreply, assign(socket, form: to_form(%{"email" => email}, as: "user"), errors: errors)}

      {:error, reason} ->
        Sentry.capture_message("Sign-in email failed to send", extra: %{reason: inspect(reason)})

        {:noreply,
         put_flash(
           socket,
           :error,
           "We couldn't send the email. Please try again in a few minutes."
         )}
    end
  end

  defp sent(socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Check your email for a link to sign in.")
     |> push_navigate(to: ~p"/users/log-in")}
  end

  # No challenge held: the socket reconnected mid-prompt, or a stray event.
  defp authenticate(socket, nil, _params),
    do: {:noreply, put_flash(socket, :error, PasskeyMessages.failed())}

  defp authenticate(socket, challenge, params) do
    case Passkeys.authenticate(challenge, params) do
      {:ok, user, key} ->
        token = Accounts.generate_passkey_login_token(user, key)

        {:noreply,
         assign(socket,
           passkey_form: to_form(%{"token" => token}, as: "passkey"),
           passkey_trigger: true
         )}

      {:error, :invalid_response} ->
        {:noreply, put_flash(socket, :error, PasskeyMessages.rejected())}
    end
  end

  defp request_for(%{"for" => "autofill"}), do: "autofill"
  defp request_for(_params), do: "button"

  defp user_for(email) do
    case Accounts.get_user_by_email(email) do
      nil -> Accounts.register_user(%{email: email})
      user -> {:ok, user}
    end
  end

  defp local_mail_adapter? do
    Application.get_env(:everyday_citizen, EverydayCitizen.Mailer)[:adapter] ==
      Swoosh.Adapters.Local
  end
end
