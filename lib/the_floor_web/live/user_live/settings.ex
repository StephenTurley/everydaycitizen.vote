defmodule TheFloorWeb.UserLive.Settings do
  @moduledoc """
  The account page: the email, and signing out. Changing the email needs a
  recent sign-in (sudo mode); the rest of the page does not.
  """
  use TheFloorWeb, :live_view

  alias TheFloor.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="pt-10 pb-4 flex flex-col gap-1">
        <h1 class="m-0 text-[28px] leading-tight font-bold tracking-tight">Your account</h1>
        <p class="m-0 text-[15px] text-floor-muted">{@current_email}</p>
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
       email_form: to_form(Accounts.change_user_email(user, %{}, validate_unique: false))
     )}
  end

  @impl true
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
end
