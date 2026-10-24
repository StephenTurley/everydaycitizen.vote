defmodule TheFloorWeb.UserLive.Login do
  @moduledoc """
  Sign in, or create an account, by emailed link: there are no passwords. An
  email with no account gets one (unconfirmed until the link is used). The reply
  is the same either way, so the page does not reveal who has an account.
  Signed in, it re-confirms the person for sensitive changes.
  """
  use TheFloorWeb, :live_view

  alias TheFloor.Accounts

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
          autocomplete="username"
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
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    {:ok, assign(socket, form: to_form(%{"email" => email}, as: "user"), errors: [])}
  end

  @impl true
  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    case user_for(String.trim(email)) do
      {:ok, user} ->
        Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))

        {:noreply,
         socket
         |> put_flash(:info, "Check your email for a link to sign in.")
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, changeset} ->
        errors =
          for {msg, _opts} <- Keyword.get_values(changeset.errors, :email), do: "Email #{msg}."

        {:noreply, assign(socket, form: to_form(%{"email" => email}, as: "user"), errors: errors)}
    end
  end

  defp user_for(email) do
    case Accounts.get_user_by_email(email) do
      nil -> Accounts.register_user(%{email: email})
      user -> {:ok, user}
    end
  end

  defp local_mail_adapter? do
    Application.get_env(:the_floor, TheFloor.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
